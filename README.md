# intensity-factor

This data field compute intensity & efficiency factor for either pace or power. Both are averaged over the last 3-120 seconds.

- The intensity factor (IF) is the ratio between current power (resp. pace) and the FTP (resp. FTPa). 

- The efficiency factor (EF) is the ratio between current IF and percentage of threshold heart rate (%THR). 

It is not the usual EF formula, but I designed it so EF can be compared between sessions whether it has been based on power or pace (provided that sessions when it was based on pace have been ran on a rather flat terrain!).

As an example, if you are running at your FTPa or FTP, you should be at your THR, thus resulting in EF = 1. If it is lower, it may be that it is a hot day, or that you are more tired than usual (assuming that the FTP, FTPa and THR declared in the application settings are accurate).

EF generally decreases during session, enabling to assess aerobic decoupling (not provided by this data field).

Notes :
- even if you choose to display power or pace (averaged over the last 3-120 seconds), only IF and EF will be recorded in the Fit file.
- this works best with Garmin device data recording parameter set to "every second" !
