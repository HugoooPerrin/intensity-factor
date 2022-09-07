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
    var THR;
    var rolling_duration;

    // Set the label of the data field here.
    function initialize() {
        SimpleDataField.initialize();

        // Collect user settings
        metric_id = Application.getApp().getProperty("METRIC_ID").toNumber();
        datafield_id = Application.getApp().getProperty("DATAFIELD_ID").toNumber();
        rolling_duration = Application.getApp().getProperty("WINDOW").toNumber();
        THR = Application.getApp().getProperty("THR").toNumber();

        // Chosen metric
        if (metric_id == 0) {
            rFTP = Application.getApp().getProperty("RFTP").toFloat();
            label = "POWER";
        } else {
            rFTP = Application.getApp().getProperty("RFTPa").toFloat();
            label = "PACE";
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
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>"%FTP"}
        );
        intensityFitField.setData(0);

        // Create the custom efficiency FIT data field we want to record
        efficiencyFitField = createField(
            "Efficiency factor",
            1,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>"%FTP / %THR"}
        );
        efficiencyFitField.setData(0);
    }

    // Reset metric queue & lag when starting or restarting activity
    // (to prevent from decreasing value while effort is increasing since resuming activity)
    function onTimerStart() {
        metric = new Queue(rolling_duration + 1);
        heart_rate = new Queue(rolling_duration + 1);
        lag = 0;
        // System.println("started");
    }

    function onTimerResume() {
        metric = new Queue(rolling_duration + 1);
        heart_rate = new Queue(rolling_duration + 1);
        lag = 0;
        // System.println("restarted");
    }

    // Reset metric queue when starting a new workout step 
    // to be directly accurate related to targeted effort
    // (but no need for lag because already in movement)
    function onWorkoutStepComplete() {
        metric = new Queue(rolling_duration + 1);
        heart_rate = new Queue(rolling_duration + 1);
        // System.println("new workout step");
    }

    // Computing variable
    var metric;
    var metric_counter;
    var metric_sum;
    var heart_rate;
    var heart_rate_counter;
    var heart_rate_sum;
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
            } else {
                metric.update(info.currentSpeed);
            }
        
            // Init counters for metric
            metric_counter = 0;
            metric_sum = 0.0;

            // Compute rolling sum for metric
            for (var i = 0; i < metric.length; i++) {

                // Ignore null
                if (metric.queue[i] == null) {
                    continue;
                }

                metric_sum += metric.queue[i];
                metric_counter++;
            }

            // Compute rolling mean for metric
            if (metric_counter == 0) {
                val = 0.0;
            } else {
                val = metric_sum / metric_counter;
            }

            // Init counters for heart rate
            heart_rate_counter = 0;
            heart_rate_sum = 0.0;

            // Compute rolling sum for heart rate
            for (var i = 0; i < heart_rate.length; i++) {

                // Ignore null
                if (heart_rate.queue[i] == null) {
                    continue;
                }

                heart_rate_sum += heart_rate.queue[i];
                heart_rate_counter++;
            }

            // Compute rolling mean for heart rate
            // and convert to %THR
            if (heart_rate_counter == 0) {
                hr = 0.0;
            } else {
                hr = heart_rate_sum / heart_rate_counter;
                hr /= THR;
            }

            // Saving IF to fit file
            intensity_factor = Math.round(100 * val / rFTP).toNumber();
            intensityFitField.setData(intensity_factor);

            // Saving EF to fit file
            if (hr == 0) {
                efficiency_factor = 0;
            } else {
                efficiency_factor = (val / rFTP) / hr;
            }
            efficiencyFitField.setData(efficiency_factor);

            // Format final value to display
            if (datafield_id == 0) {
                val = intensity_factor;

            } else if (metric_id == 0) {
                val = Math.round(val).toNumber();

            } else if ((metric_id == 1) & (val != 0)) {
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
            val = 0;

        } else {
            val = 0;
        }

        if (val == 0) {
            val = "--";
        }
        
        // // Monitoring & debugging
        // if (metric != null) {
        //     System.println(metric.queue);
        // }

        return val;
    }
}