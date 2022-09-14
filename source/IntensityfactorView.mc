using Toybox.Activity;
using Toybox.Lang;
using Toybox.Time;
using Toybox.WatchUi;
using Toybox.Math;
using Toybox.Application;
using Toybox.FitContributor;


// ROLLING QUEUE CLASS
class Queue {

    // Init
    var length;
    var queue;
    var counter;
    var sum;

    // Initialize instance
    function initialize(len) {
        length = len;
        queue = new [len];
    }

    // Add a member to queue
    function update(member) {
        for (var i = self.length-1; i > 0; i--) {
            self.queue[i] = self.queue[i-1];
        }
        self.queue[0] = member;
    }

    // Compute mean (taking null into account)
    function mean() {
        counter = 0;
        sum = 0.0;

        // Compute rolling sum for metric
        for (var i = 0; i < self.length; i++) {

            // Ignore null
            if (self.queue[i] == null) {
                continue;
            }

            sum += self.queue[i];
            counter++;
        }

        // Return average
        return (counter != 0) ? sum / counter : 0.0;
    }

    // Get current
    function current(n) {
        return Math.mean(self.queue.slice(0, n));
    }

    // Get last (not null)
    function last(n) {
        for (var i = self.length-1; i >= n-1; i--) {
            if (self.queue[i] != null) {
                return Math.mean(self.queue.slice(i+1-n, i+1));
            } else {
                continue;
            }
        }
        return null;
    }

    // Get non-null count
    function count_not_null() {
        counter = self.length;
        for (var i = self.length-1; i >= 0; i--) {
            if (self.queue[i] != null) {
                return counter;
            } else {
                counter--;
                continue;
            }
        }
        return 0;
    }
}


// GAP modelling
// ref : https://www.reddit.com/r/Strava/comments/sdeix0/mind_the_gap_getting_fit_for_the_formula_equation/
function gap_factor(g) {
    return 1 + 0.02869556 * g + 0.001520768 * g * g;
}


// MAIN DATA FIELD CLASS
class IntensityfactorView extends WatchUi.SimpleDataField {

    // General settings
    // const heart_rate_lag = 15;
    const ignore_first = 5;
    var lag = 0;

    // Application settings
    var metric_id;
    var datafield_id;
    var rFTP;
    var rolling_duration;
    var display_grade;

    // Fit fields
    var intensityFitField;
    var efficiencyFitField;
    var speedFitField;
    var gradeFitField;
    var altitudeFitField;

    // Set the label of the data field here.
    function initialize() {
        SimpleDataField.initialize();

        // Collect user settings
        metric_id = Application.getApp().getProperty("METRIC_ID").toNumber();
        datafield_id = Application.getApp().getProperty("DATAFIELD_ID").toNumber();
        rolling_duration = Application.getApp().getProperty("WINDOW").toNumber()+1;
        display_grade = Application.getApp().getProperty("GRADE");

        // Chosen metric
        if (metric_id == 0) {
            rFTP = Application.getApp().getProperty("RFTP").toFloat();
            label = "POWER";
        } else {
            rFTP = Application.getApp().getProperty("RFTPa").toFloat();
            label = (metric_id == 1) ? "PACE" : "GAP";
        }

        // Update label name if IF chosen
        if (datafield_id == 0) {
            label += " INTENSITY";
        }

        // Create the custom intensity FIT data field we want to record
        intensityFitField = createField(
            "Intensity factor",
            0,
            FitContributor.DATA_TYPE_UINT16,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>"%"}
        );
        intensityFitField.setData(0);

        // Create the custom efficiency FIT data field we want to record
        efficiencyFitField = createField(
            "Efficiency factor",
            1,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
        );
        efficiencyFitField.setData(0);

        // Create the custom grade FIT data field we want to record
        gradeFitField = createField(
            "Grade",
            2,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
        );
        gradeFitField.setData(0);

        // TO DEBUG GRADE IF NEEDED
        // Create the custom speed FIT data field we want to record
        speedFitField = createField(
            "Speed",
            3,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
        );
        speedFitField.setData(0);

        // Create the custom speed FIT data field we want to record
        altitudeFitField = createField(
            "Altitude",
            4,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
        );
        altitudeFitField.setData(0);
    }

    // Reset metric queue & lag when starting or restarting activity
    // (to prevent from decreasing value while effort is increasing since resuming activity)
    function reset_queues() {
        heart_rate = new Queue(rolling_duration);
        speed = new Queue(rolling_duration);
        altitude = new Queue(rolling_duration);
        if (metric_id == 0) {
            power = new Queue(rolling_duration);
        }
        lag = 0;
    }
    function onTimerStart() {
        reset_queues();
        // System.println("started");
    }

    function onTimerResume() {
        reset_queues();
        // System.println("restarted");
    }

    // Reset metric queue when starting a new workout step (NOT A SIMPLE LAP)
    // to be directly accurate related to targeted effort
    function onWorkoutStepComplete() {
        reset_queues();
        // System.println("new workout step");
    }

    // Computing variable
    var power;
    var pwr;
    var heart_rate;
    var hr;
    var speed;
    var spd;
    var altitude;
    var grade;
    var gap;
    var dist;
    var n_seconds;
    var intensity_factor;
    var efficiency_factor;
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
        // else return 0.0 and reset rolling queue
        
        if (lag >= ignore_first) {

            // Add new value to rolling queue
            // (Oldest member is automatically removed)
            heart_rate.update(info.currentHeartRate);
            speed.update(info.currentSpeed);
            altitude.update(info.altitude);

            if (metric_id == 0) {
                power.update(info.currentPower);

                // Compute rolling mean for power
                pwr = power.mean();
            }

            // Compute rolling mean for speed
            spd = speed.mean();

            // Compute rolling mean for heart rate
            hr = heart_rate.mean();

            // Compute rolling grade
            // Count how many values are stored in queues
            n_seconds = altitude.count_not_null();

            // Get distance using val which is speed (mps)
            dist = spd * n_seconds;

            // Compute grade (%) and clip to 40% to prevent abnormal values
            // (n_seconds >= 2) would be enough but 5 is more robust when starting
            grade = ((n_seconds >= 5) & (dist > 1)) ? 100 * (altitude.current(2) - altitude.last(2)) / dist : 0;
            grade = (grade < 40) ? grade : 40;
            grade = (grade > -40) ? grade : -40;

            // Compute adjusted pace
            gap = spd * gap_factor(grade);
            spd = (metric_id == 2) ? gap : spd;

            // Saving grade to fit file
            gradeFitField.setData(grade);
            altitudeFitField.setData(info.altitude);
            speedFitField.setData(info.currentSpeed);

            // // Monitoring
            // System.println(metric.queue);
            // System.println(altitude.queue);
            // if (n_seconds >= 5) {
            //     System.println(altitude.current(2));
            //     System.println(altitude.last(2));
            // }

            // Saving IF to fit file
            intensity_factor = (metric_id == 0) ? 100 * pwr / rFTP : 100 * spd / rFTP;
            intensity_factor = Math.round(intensity_factor).toNumber();
            intensityFitField.setData(intensity_factor);

            // Saving EF to fit file : always based on GAP for comparison and unit is mpm/bpm
            efficiency_factor = (hr != 0) ? 60 * gap / hr : 0;
            efficiencyFitField.setData(efficiency_factor);

            // Format final value to display
            if (datafield_id == 0) {
                val = intensity_factor;

            } else if (metric_id == 0) {
                val = Math.round(pwr).toNumber();

            // Works for pace or gap
            } else if (spd != 0) {
                pace = 60.0 / (spd * 3.6);
                mins = Math.floor(pace).toNumber();
                secs = Math.round((pace - mins) * 60);
                // handling one special case
                if (secs == 60) {
                    mins += 1;
                    secs = 0;
                }
                val = Lang.format("$1$:$2$", [mins.format("%d"), secs.format("%02d")]);
            }

            // Show grade next to value
            val = (display_grade & ((datafield_id == 0) | (metric_id == 0))) ? Lang.format("$1$:$2$", [val, Math.round(grade).format("%d")]) : val;
        
        } else if (info.timerState == 3) {
            // Increase lag counter
            lag++;
            val = "--";

        } else {
            val = "--";
        }
        
        // // Monitoring & debugging
        // if (metric != null) {
        //     System.println(metric.queue);
        // }

        return val;
    }
}