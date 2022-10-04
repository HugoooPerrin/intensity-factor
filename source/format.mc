using Toybox.Math;

var pace;
var mins;
var secs;

function to_pace(speed) {

    // Convert to pace
    pace = 60.0 / (speed * 3.6);
    mins = Math.floor(pace).toNumber();
    secs = Math.round((pace - mins) * 60);
    
    // handling one special case
    if (secs == 60) {
        mins += 1;
        secs = 0;
    }

    return [mins, secs];
}