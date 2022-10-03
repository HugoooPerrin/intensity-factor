using Toybox.Activity;
using Toybox.Lang;
using Toybox.Time;
using Toybox.WatchUi;
using Toybox.Math;
using Toybox.Application;
using Toybox.FitContributor;


// GAP modelling
// ref : https://www.reddit.com/r/Strava/comments/sdeix0/mind_the_gap_getting_fit_for_the_formula_equation/
function grade_factor(g) {
    return 1 + 0.02869556 * g + 0.001520768 * g * g;
}


// MAIN DATA FIELD CLASS
class IntensityfactorView extends WatchUi.SimpleDataField {

    // General settings
    const ignore_first = 5;
    var lag = 0;

    // Application settings
    var metric_id;
    var datafield_id;
    var rFTP;
    var rolling_duration;
    var rolling_duration_grade;
    var display_grade;
    var debug_mode;
    var zones = new [7];

    // Fit fields
    var gapFitField;
    var intensityFitField;
    var efficiencyFitField;
    var gradeFitField;

    // Debug fit fields
    var powerFitField;
    var speedFitField;
    var altitudeFitField;

    // Set the label of the data field here.
    function initialize() {
        SimpleDataField.initialize();

        // Collect user settings
        metric_id = Application.getApp().getProperty("METRIC_ID").toNumber();
        datafield_id = Application.getApp().getProperty("DATAFIELD_ID").toNumber();
        rolling_duration = Application.getApp().getProperty("WINDOW").toNumber()+1;
        rolling_duration_grade = Application.getApp().getProperty("WINDOW_GRADE").toNumber()+1;
        display_grade = Application.getApp().getProperty("GRADE");
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
        if (metric_id == 0) {
            rFTP = Application.getApp().getProperty("RFTP").toFloat();
            label = "POWER";
        } else {
            rFTP = Application.getApp().getProperty("RFTPa").toFloat();
            label = (metric_id == 1) ? "PACE" : "GAP";
        }

        // Update label name if IF chosen
        if (datafield_id == 1) {
            label += " INTENSITY";
        } else if (datafield_id == 2) {
            label += " ZONE";
        }

        // GRAPH FIT FIELDS
        // Create the custom GAP FIT data field we want to record
        gapFitField = createField(
            "GAP",
            0,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
        );
        gapFitField.setData(0);

        // Create the custom intensity FIT data field we want to record
        intensityFitField = createField(
            "Intensity factor",
            1,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
        );
        intensityFitField.setData(0);

        // Create the custom grade FIT data field we want to record
        gradeFitField = createField(
            "Grade",
            3,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
        );
        gradeFitField.setData(0);

        // LAP FIT FIELDS : TO COME !!
        // OVERALL FIT FIELDS : TO COME !!

        // TO DEBUG GRADE | POWER IF NEEDED
        if (debug_mode) {
            // Create the custom speed FIT data field we want to record
            powerFitField = createField(
                "Power API",
                8,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
            );
            powerFitField.setData(0);

            // Create the custom speed FIT data field we want to record
            speedFitField = createField(
                "Speed API",
                9,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
            );
            speedFitField.setData(0);

            // Create the custom speed FIT data field we want to record
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
        gap = new Queue(rolling_duration);

        altitude = new Queue(rolling_duration_grade);
        if (metric_id == 0) {
            power = new Queue(rolling_duration);
        }
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
    var power;
    var rolling_pwr;
    var speed;
    var rolling_spd;
    var altitude;
    var grade;
    var gap;
    var rolling_gp;
    var instant_gap;
    var dist;
    var n_seconds;
    var intensity_factor;
    var zone_num;
    var zone_prct;
    var val;
    var pace;
    var mins;
    var secs;

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info as Activity.Info) as Numeric or Duration or String or Null {

        // Update rolling queues, compute value & save to fit file
        if (lag >= ignore_first) {

            // Debug mode
            if (debug_mode) {
                powerFitField.setData((info.currentPower != null) ? info.currentPower : 0);
                speedFitField.setData((info.currentSpeed != null) ? info.currentSpeed * 3.6 : 0);
                altitudeFitField.setData((info.altitude != null) ? info.altitude : 0);
            }

            // Add new value to rolling queue (oldest member is automatically removed)
            speed.update((info.currentSpeed != null) ? info.currentSpeed : 0);
            altitude.update((info.altitude != null) ? info.altitude : 0);

            // Compute rolling mean for speed
            rolling_spd = speed.mean();

            if (metric_id == 0) {
                // Add new value to queue (oldest member is automatically removed)
                power.update((info.currentPower != null) ? info.currentPower : 0);

                // Compute rolling mean for power
                rolling_pwr = power.mean();
            }

            // INSTANT GRADE AND GAP
            // Count how many values are stored in altitude queue 
            // (potentially shorter than other : rolling_duration_grade <= rolling_duration)
            n_seconds = altitude.count_not_null();

            // Get distance estimate using enhanced speed (mps)
            dist = speed.current(n_seconds) * n_seconds;

            // Compute instant grade (%) and clip to 40% to prevent abnormal values
            grade = ((n_seconds >= 5) & (dist > 1)) ? 100 * (altitude.current(2) - altitude.last(2)) / dist : 0;
            grade = (grade < 40) ? grade : 40;
            grade = (grade > -40) ? grade : -40;

            // Saving grade to fit file
            gradeFitField.setData(grade);

            // Compute grade adjusted pace (instant)
            // (makes sense because current speed is enhanced by Garmin, therefore also has a little lag)
            instant_gap = speed.current(1) * grade_factor(grade);
            gap.update(instant_gap);

            // Compute rolling mean for grade adjusted pace
            // (Smoother than rolling_gp = rolling_speed * grade_factor(grade) ?)
            rolling_gp = gap.mean();

            // Replace according to user settings
            rolling_spd = (metric_id == 2) ? rolling_gp : rolling_spd;

            // Saving instant GAP to fit file
            gapFitField.setData(instant_gap * 3.6);

            // Saving rolling IF to fit file
            intensity_factor = (metric_id == 0) ? 100 * rolling_pwr / rFTP : 100 * rolling_spd / rFTP;
            intensityFitField.setData(Math.round(intensity_factor).toNumber());

            // Format final value to display
            if (datafield_id == 1) {
                // Show grade next to intensity
                val = Math.round(intensity_factor).toNumber();
                val = (display_grade) ? Lang.format("$1$:$2$", [val, Math.round(grade).format("%d")]) : val.format("%.0f") + "%";

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

            } else if (metric_id == 0) {
                val = Math.round(rolling_pwr).toNumber();

            // Works for pace or gap
            } else if (rolling_spd != 0) {
                pace = 60.0 / (rolling_spd * 3.6);
                mins = Math.floor(pace).toNumber();
                secs = Math.round((pace - mins) * 60);
                // handling one special case
                if (secs == 60) {
                    mins += 1;
                    secs = 0;
                }
                val = Lang.format("$1$:$2$", [mins.format("%d"), secs.format("%02d")]);
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