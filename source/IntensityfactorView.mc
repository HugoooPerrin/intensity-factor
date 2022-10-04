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
    var LTHR;
    var rolling_duration;
    var rolling_duration_grade;
    var debug_mode;
    var zones = new [7];

    // Fit fields
    var gapFitField;
    var intensityFitField;
    var efficiencyFitField;
    var gradeFitField;

    // LAP fit fields
    var LapIntensityFitField;
    var LapEfficiencyFitField;
    var LapGapFitField;

    // Overall fit fields
    var OverallIntensityFitField;
    var OverallEfficiencyFitField;
    var OverallGapFitField;

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
        LTHR = Application.getApp().getProperty("LTHR").toFloat();
        rFTP = (metric_id == 0) ? Application.getApp().getProperty("RFTP") : Application.getApp().getProperty("RFTPa");
        rFTP = rFTP.toFloat();

        // Set label name based on chosen datafield and metric
        if (datafield_id == 0) {
            label = "POWER";
        } else if (datafield_id == 1) {
            label = "PACE";
        } else if (metric_id == 0) {
            label = "POWER";
        } else if (metric_id == 1) {
            label = "PACE";
        } else if (metric_id == 2) {
            label = "GAP";
        }
        
        if (datafield_id == 2) {
            label += " INTENSITY";
        } else if (datafield_id == 3) {
            label += " ZONES";
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

        // Create the custom efficiency FIT data field we want to record
        efficiencyFitField = createField(
            "Running efficiency",
            2,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
        );
        efficiencyFitField.setData(0);

        // Create the custom grade FIT data field we want to record
        gradeFitField = createField(
            "Grade",
            3,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
        );
        gradeFitField.setData(0);

        // LAP FIT FIELDS
        // Create the custom lap GAP FIT data field we want to record
        LapGapFitField = createField(
            "Lap GAP",
            4,
            FitContributor.DATA_TYPE_STRING,
            {:mesgType=>FitContributor.MESG_TYPE_LAP, :units=>"", :count=>7}
        );
        LapGapFitField.setData("");

        // Create the custom lap intensity FIT data field we want to record
        LapIntensityFitField = createField(
            "Lap intensity factor",
            5,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType=>FitContributor.MESG_TYPE_LAP, :units=>""}
        );
        LapIntensityFitField.setData(0);

        // Create the custom lap efficiency FIT data field we want to record
        LapEfficiencyFitField = createField(
            "Lap running efficiency",
            6,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_LAP, :units=>""}
        );
        LapEfficiencyFitField.setData(0);

        // OVERALL FIT FIELDS
        // Create the custom overall GAP FIT data field we want to record
        OverallGapFitField = createField(
            "Overall GAP",
            11,
            FitContributor.DATA_TYPE_STRING,
            {:mesgType=>FitContributor.MESG_TYPE_SESSION, :units=>"", :count=>7}
        );
        OverallGapFitField.setData("");

        // Create the custom overall intensity FIT data field we want to record
        OverallIntensityFitField = createField(
            "Overall intensity factor",
            12,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType=>FitContributor.MESG_TYPE_SESSION, :units=>""}
        );
        OverallIntensityFitField.setData(0);

        // Create the custom overall efficiency FIT data field we want to record
        OverallEfficiencyFitField = createField(
            "Overall running efficiency",
            13,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_SESSION, :units=>""}
        );
        OverallEfficiencyFitField.setData(0);

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
        heart_rate = new Queue(rolling_duration);

        power = new Queue(rolling_duration);
        speed = new Queue(rolling_duration);

        gap = new Queue(rolling_duration);
        altitude = new Queue(rolling_duration_grade);

        lag = 0;
    }

    function reset_lap_data() {
        lap_counter = 0;

        lap_if_acc = 0;
        lap_re_acc = 0;
        lap_gap_acc = 0;
    }

    function reset_overall_data() {
        overall_counter = 0;

        overall_if_acc = 0;
        overall_re_acc = 0;
        overall_gap_acc = 0;
    }

    function onTimerStart() {
        reset_queues();
        reset_lap_data();
        reset_overall_data();
    }

    function onTimerResume() {
        reset_queues();
    }

    // Reset metric queue when starting a new workout step (NOT A SIMPLE LAP)
    // to be directly accurate related to targeted effort
    function onWorkoutStepComplete() {
        reset_queues();
        reset_lap_data();
    }

    function onTimerLap() {
        reset_lap_data();
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
    var heart_rate;
    var intensity_factor;
    var efficiency;
    var zone_num;
    var zone_prct;
    var val;
    var pace;

    // Lap variable
    var lap_counter;
    var lap_if_acc;
    var lap_re_acc;
    var lap_gap_acc;
    var lap_gap_pace;

    // Overall variable
    var overall_counter;
    var overall_if_acc;
    var overall_re_acc;
    var overall_gap_acc;
    var overall_gap_pace;

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

            // MAIN COMPUTING PART
            // Add new values to rolling queue (oldest member is automatically removed)
            heart_rate.update((info.currentHeartRate != null) ? info.currentHeartRate : 0);
            power.update((info.currentPower != null) ? info.currentPower : 0);
            speed.update((info.currentSpeed != null) ? info.currentSpeed : 0);
            altitude.update((info.altitude != null) ? info.altitude : 0);

            // Compute rolling mean for speed & power
            rolling_spd = speed.mean();
            rolling_pwr = power.mean();

            // Compute grade and GAP
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

            // Compute rolling mean for GAP
            rolling_gp = gap.mean();

            // Saving instant GAP to fit file
            gapFitField.setData(instant_gap * 3.6);

            // Computing IF and saving to fit file
            if (metric_id == 0) {
                intensity_factor = 100 * rolling_pwr / rFTP;
            } else if (metric_id == 1) {
                intensity_factor =  100 * rolling_spd / rFTP;
            } else if (metric_id == 2) {
                intensity_factor =  100 * rolling_gp / rFTP;
            }
            intensityFitField.setData(Math.round(intensity_factor).toNumber());

            // Computing running efficiency (intensity_factor is already a rolling avg)
            efficiency = (intensity_factor != 0) ? (heart_rate.mean() / LTHR) / intensity_factor : 0;
            efficiencyFitField.setData(efficiency);

            // DISPLAY VALUE
            // Power
            if (datafield_id == 0) {
                val = Math.round(rolling_pwr).toNumber();

            // Pace
            } else if ((datafield_id == 1) & (rolling_spd != 0)) {
                pace = to_pace(rolling_spd);
                val = Lang.format("$1$:$2$", [pace[0].format("%d"), pace[1].format("%02d")]);

            // Intensity
            } else if (datafield_id == 2) {
                val = Math.round(intensity_factor).toNumber().format("%d") + "%";

            // Zones
            } else if (datafield_id == 3) {
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

            // LAP VALUES
            lap_counter++;

            lap_gap_acc += instant_gap; // instant value
            lap_gap_pace = to_pace(lap_gap_acc / lap_counter);
            LapGapFitField.setData(Lang.format("$1$:$2$", [lap_gap_pace[0].format("%d"), lap_gap_pace[1].format("%02d")]));

            lap_if_acc += intensity_factor; // rolling value
            LapIntensityFitField.setData(lap_if_acc / lap_counter);

            lap_re_acc += efficiency; // rolling value
            LapEfficiencyFitField.setData(lap_re_acc / lap_counter);

            // OVERALL VALUES
            overall_counter++;

            overall_gap_acc += instant_gap; // instant value
            overall_gap_pace = to_pace(overall_gap_acc / overall_counter);
            OverallGapFitField.setData(Lang.format("$1$:$2$", [overall_gap_pace[0].format("%d"), overall_gap_pace[1].format("%02d")]));

            overall_if_acc += intensity_factor; // rolling value
            OverallIntensityFitField.setData(overall_if_acc / overall_counter);

            overall_re_acc += efficiency; // rolling value
            OverallEfficiencyFitField.setData(overall_re_acc / overall_counter);

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