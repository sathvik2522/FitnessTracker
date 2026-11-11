# Apple Health

The explicit Connect action requests **read only**: basal/resting energy, active energy, steps, body mass and workouts. Sleep analysis is separately opted in; HRV SDNN and resting heart rate have another separate recovery opt-in. No write permissions are requested. Respiratory rate, oxygen saturation, wrist temperature and HR-series are not connected.

HealthKit does not provide a definitive read-denial signal for every type. An empty response may mean missing samples or unavailable access; the app must not treat it as a measured zero. Cumulative quantities use HealthKit statistics with local calendar-day windows, including daylight-saving transitions. Workout records are not added to energy totals. Current-day data is partial and can change.

The app contains `NSHealthShareUsageDescription` and a HealthKit entitlement. Simulator builds do not establish actual watch synchronization or device permission behavior. Verify on a supported physical iPhone after explicit approval; data sources and sync timing can differ.
