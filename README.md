# intensity-factor

This data field computes intensity factor and zones for either pace, grade-adjusted pace (GAP) or power. All values can be averaged over the last 15-120 seconds.

- The intensity factor (IF) is the ratio between current power (resp. pace or GAP) and the FTP (resp. FTPa).
- The intensity zones can be customized in the app settings.
- You can also choose to display a "raw" value (power, pace or GAP). It will also be averaged over the last 15-120 seconds.

- rFTP (resp rFTPa) is the maximum power (resp pace) that you can, when rested, sustain during a one hour race
- LTHR is the lactacte threshold heart rate. Same than above. It generally is between 85-95% of heart rate reserve.

Running efficiency is saved in lap, session and charts. It is computed as the ratio between %LTHR and %FTP. It represents a proxy for cardio drift (during steady aerobic effort) as shown by Stephen Seiler (see https://www.youtube.com/watch?v=3GXc474Hu5U). Though it is not exactly the same formula, it has the same dynamic and values should be similar !

GAP is computed by relying on Strava model :
- https://www.reddit.com/r/Strava/comments/sdeix0/mind_the_gap_getting_fit_for_the_formula_equation/

Notes :
- this datafield works only with Garmin device data recording parameter set to "every second" !
