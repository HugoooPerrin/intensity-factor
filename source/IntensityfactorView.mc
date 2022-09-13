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
    function current() {
        return self.queue[0];
    }

    // Get last (not null)
    function last() {
        for (var i = self.length-1; i >= 0; i--) {
            if (self.queue[i] != null) {
                return self.queue[i];
            } else {
                continue;
            }
        }
        return null;
    }

    // Get non-null count
    function count_not_null() {
        counter = 0;
        for (var i = self.length-1; i >= 0; i--) {
            if (self.queue[i] != null) {
                return counter;
            } else {
                counter++;
                continue;
            }
        }
        return self.length;
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
    var intensityFitField;
    var efficiencyFitField;
    var rFTP;
    var rolling_duration;

    // Set the label of the data field here.
    function initialize() {
        SimpleDataField.initialize();

        // Collect user settings
        metric_id = Application.getApp().getProperty("METRIC_ID").toNumber();
        datafield_id = Application.getApp().getProperty("DATAFIELD_ID").toNumber();
        rolling_duration = Application.getApp().getProperty("WINDOW").toNumber();

        // Chosen metric
        if (metric_id == 0) {
            rFTP = Application.getApp().getProperty("RFTP").toFloat();
            label = "POWER";
        } else if (metric_id == 1) {
            rFTP = Application.getApp().getProperty("RFTPa").toFloat();
            label = "PACE";
        } else {
            rFTP = Application.getApp().getProperty("RFTPa").toFloat();
            label = "GAP";
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
    }

    // Reset metric queue & lag when starting or restarting activity
    // (to prevent from decreasing value while effort is increasing since resuming activity)
    function onTimerStart() {
        metric = new Queue(rolling_duration + 1);
        heart_rate = new Queue(rolling_duration + 1);
        distance = new Queue(rolling_duration + 1);
        time = new Queue(rolling_duration + 1);
        if (metric_id == 2) {
            altitude = new Queue(rolling_duration + 1);
        }
        lag = 0;
        // System.println("started");
    }

    function onTimerResume() {
        metric = new Queue(rolling_duration + 1);
        heart_rate = new Queue(rolling_duration + 1);
        distance = new Queue(rolling_duration + 1);
        time = new Queue(rolling_duration + 1);
        if (metric_id == 2) {
            altitude = new Queue(rolling_duration + 1);
        }
        lag = 0;
        // System.println("restarted");
    }

    // Reset metric queue when starting a new workout step 
    // to be directly accurate related to targeted effort
    function onWorkoutStepComplete() {
        metric = new Queue(rolling_duration + 1);
        heart_rate = new Queue(rolling_duration + 1);
        distance = new Queue(rolling_duration + 1);
        time = new Queue(rolling_duration + 1);
        if (metric_id == 2) {
            altitude = new Queue(rolling_duration + 1);
        }
        lag = 0;
        // System.println("new workout step");
    }

    // Computing variable
    var speed;
    var distance;
    var running_distance;
    var time;
    var running_time;
    var metric;
    var heart_rate;
    var altitude;
    var current_altitude;
    var latest_altitude;
    var grade;
    var dist;
    var n_points;
    var intensity_factor;
    var efficiency_factor;
    var hr;
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
            if (metric_id == 0) {
                metric.update(info.currentPower);
            } else if (metric_id == 1) {
                metric.update(info.currentSpeed);
            } else {
                metric.update(info.currentSpeed);
                distance.update(info.elapsedDistance);
                time.update(info.timerTime);
                altitude.update(info.altitude);
            }

            // Compute rolling mean for metric
            val = metric.mean();

            // Compute rolling mean for heart rate
            hr = heart_rate.mean();

            // // Compute speed
            // // Get current distance
            // running_distance = distance.current() - distance.last();
            // running_time = time.current() - time.last();
            // speed = (running_time != 0) ? 1000 * running_distance / running_time : info.currentSpeed;

            // Compute averaged grade
            if (metric_id == 2) {

                // Get current altitude
                current_altitude = altitude.current();

                // Get latest altitude available
                latest_altitude = altitude.last();
                n_points = altitude.count_not_null();

                // Get distance using val which is speed (mps)
                // Cannot take metric_sum because of special case when the queue is not entirely filled
                // (at start time or resume for instance)
                dist = val * n_points;

                // Compute grade (%) and clip to 40% to prevent abnormal values
                grade = ((n_points >= 2) & (dist != 0)) ? 100 * (current_altitude - latest_altitude) / dist : 0;
                grade = (grade < 40) ? grade : 40;
                grade = (grade > -40) ? grade : -40;

                // Compute adjusted pace
                val *= gap_factor(grade);

                // Monitoring
                // System.println(metric.queue);
                // System.println(altitude.queue);
                // System.println(dist);
            }

            // Saving IF to fit file
            intensity_factor = Math.round(100 * val / rFTP).toNumber();
            intensityFitField.setData(intensity_factor);

            // Saving EF to fit file : unit is mpm / bpm
            efficiency_factor = (hr != 0) ? 60 * val / hr : 0;
            efficiencyFitField.setData(efficiency_factor);

            // Format final value to display
            if (datafield_id == 0) {
                val = intensity_factor;

            } else if (metric_id == 0) {
                val = Math.round(val).toNumber();

            // Works for pace or gap
            } else if (val != 0) {
                pace = 60.0 / (val * 3.6);
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

            if (metric_id == 2) {
                altitude.update(info.altitude);
            }

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