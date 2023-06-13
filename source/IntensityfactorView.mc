import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Math;
import Toybox.Application;
import Toybox.FitContributor;


// GAP modelling
// ref : https://www.reddit.com/r/Strava/comments/sdeix0/mind_the_gap_getting_fit_for_the_formula_equation/
function grade_factor(g) {
    return 1 + 0.02869556 * g + 0.001520768 * g * g;
}


// MAIN DATA FIELD CLASS
class IntensityfactorView extends WatchUi.SimpleDataField {

    // General settings
    const ignore_first = 10;
    var lag = 0;

    // Application settings
    var metric_id;
    var datafield_id;
    var rFTP;
    var LTHR;
    var rolling_duration;
    var rolling_duration_grade;
    var debug_mode;
    var zones = new [7];
    var threshold = new [2];

    // Fit fields
    var gapFitField;
    var intensityFitField;
    var gradeFitField;
    var vspeedFitField;

    // Debug fit fields
    var speedFitField;
    var altitudeFitField;

    // Set the label of the data field here.
    function initialize() {
        SimpleDataField.initialize();

        // Collect user settings
        datafield_id = Application.getApp().getProperty("DATAFIELD_ID").toNumber();
        rolling_duration = Application.getApp().getProperty("WINDOW").toNumber()+1;
        rolling_duration_grade = Application.getApp().getProperty("WINDOW_GRADE").toNumber()+1;
        debug_mode = Application.getApp().getProperty("DEBUG");

        // Rolling windows security net
        rolling_duration_grade = (rolling_duration < rolling_duration_grade) ? rolling_duration : rolling_duration_grade;

        // Intensity zones
        zones[0] = 0;
        for (var i = 1; i <= 5; i++) {
            zones[i] = Application.getApp().getProperty("ZONE"+i.toString()).toNumber();
        }
        zones[6] = 150;

        // Chosen metric
        rFTP = Application.getApp().getProperty("RFTPa").toFloat();

        // Set label name based on chosen datafield and metric
        if (datafield_id == 0) {
            label = "GAP";

        } else if (datafield_id == 1) {
            label = "INTENSITY";
            
        } else if (datafield_id == 2) {
            label = "ZONES";
        }

        // GRAPH FIT FIELDS
        // GAP
        gapFitField = createField(
            "GAP",
            0,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
        );
        gapFitField.setData(0);

        // Intensity factor
        intensityFitField = createField(
            "Intensity factor",
            1,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
        );
        intensityFitField.setData(0);

        // Grade
        gradeFitField = createField(
            "Grade",
            3,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
        );
        gradeFitField.setData(0);

        // Vertical speed
        vspeedFitField = createField(
            "Vertical speed",
            4,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
        );
        vspeedFitField.setData(0);

        // TO DEBUG IF NEEDED
        if (debug_mode) {
            // Garmin speed API
            speedFitField = createField(
                "Speed API",
                9,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
            );
            speedFitField.setData(0);

            // Garmin elevation API
            altitudeFitField = createField(
                "Altitude API",
                10,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
            );
            altitudeFitField.setData(0);
        }
    }

    // Reset metric queue & lag when starting or restarting activity
    // (to prevent from decreasing value while effort is increasing since resuming activity)
    function reset_queues() {
        speed = new Queue(rolling_duration);
        altitude = new Queue(rolling_duration);
        gap = new Queue(rolling_duration);
        altitude_for_grade = new Queue(rolling_duration_grade);

        lag = 0;
    }

    function onTimerStart() {
        reset_queues();
    }

    function onTimerResume() {
        reset_queues();
    }

    // Reset metric queue when starting a new workout step (NOT A SIMPLE LAP)
    // to be directly accurate related to targeted effort
    function onWorkoutStepComplete() {
        reset_queues();
    }

    // Computing variable
    var speed;
    var rolling_spd;
    var altitude;
    var altitude_for_grade;
    var grade;
    var abs_grade;
    var gap;
    var rolling_gp;
    var instant_gap;
    var vertical_speed;
    var distance;
    var n_seconds;
    var n_seconds_grade;
    var intensity_factor;
    var zone_num;
    var zone_prct;
    var val;
    var pace;

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info as Activity.Info) as Numeric or Duration or String or Null {

        // Update rolling queues, compute value & save to fit file
        if (lag >= ignore_first) {

            // Debug mode
            if (debug_mode) {
                speedFitField.setData((info.currentSpeed != null) ? info.currentSpeed * 3.6 : 0);
                altitudeFitField.setData((info.altitude != null) ? info.altitude : 0);
            }

            // MAIN COMPUTING PART
            // Add new values to rolling queue (oldest member is automatically removed)
            speed.update((info.currentSpeed != null) ? info.currentSpeed : 0);
            altitude.update((info.altitude != null) ? info.altitude : 0);
            altitude_for_grade.update((info.altitude != null) ? info.altitude : 0);

            // Compute speed rolling mean
            rolling_spd = speed.mean();

            // Compute vertical speed
            n_seconds = altitude.count_not_null();
            vertical_speed = (n_seconds >= 5) ? 3600 * (altitude.first(1) - altitude.last(1)) / n_seconds : 0;
            vspeedFitField.setData(Math.round(vertical_speed).toNumber());

            // Compute grade and GAP
            // Count how many values are stored in altitude queue 
            // (potentially shorter than other : rolling_duration_grade <= rolling_duration)
            n_seconds_grade = altitude_for_grade.count_not_null();

            // Get distance : estimate using enhanced speed (mps) (becomes - incorrectly - null at low speed in mountain...)
            distance = speed.first(n_seconds_grade) * n_seconds_grade;

            // Compute instant grade (%) and clip to 40% to prevent abnormal values
            grade = ((n_seconds_grade >= 5) & (distance > 2)) ? 100 * (altitude_for_grade.first(1) - altitude_for_grade.last(1)) / distance : 0;
            grade = (grade < 40) ? grade : 40;
            grade = (grade > -40) ? grade : -40;
            gradeFitField.setData(grade);

            // Compute instant & rolling GAP
            // (makes sense because current speed is enhanced by Garmin, therefore also has a little lag)
            instant_gap = speed.first(1) * grade_factor(grade);
            gap.update(instant_gap);
            rolling_gp = gap.mean();
            gapFitField.setData(rolling_gp * 3.6); // Saving rolling GAP to have smooth values

            // Computing intensity factor and saving to fit file
            intensity_factor =  100 * rolling_gp / rFTP;
            intensityFitField.setData(Math.round(intensity_factor).toNumber());

            // DISPLAY VALUE
            // GAP
            if (datafield_id == 0) {
                pace = to_pace(rolling_gp);
                val = Lang.format("$1$:$2$", [pace[0].format("%d"), pace[1].format("%02d")]);

            // Intensity
            } else if (datafield_id == 1) {
                val = Math.round(intensity_factor).toNumber().format("%d") + "%";

            // Zones
            } else if (datafield_id == 2) {
                // Computing zone
                for (var i = 1; i <= 6; i++) {
                    if (intensity_factor < zones[i]) {
                        zone_num = i-1;
                        zone_prct = (intensity_factor - zones[i-1]) / (zones[i] - zones[i-1]);
                        zone_prct = Math.round(10 * zone_prct).toNumber();
                        break;
                    }
                    zone_num = 6;
                    zone_prct = 0;
                }
                // handling one special case
                if (zone_prct == 10) {
                    zone_num += 1;
                    zone_prct = 0;
                }
                val = Lang.format("$1$.$2$", [zone_num.format("%d"), zone_prct.format("%d")]);
            }

        } else if (info.timerState == 3) {
            // Increase lag counter
            lag++;
            val = "--";

        } else {
            val = "--";
        }
        
        return val;
    }
}