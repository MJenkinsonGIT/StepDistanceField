//
// Step Distance Data Field
// Displays activity steps, step-based distance in miles, and rolling 10s speed in mph.
//

import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Main application class
class StepDistanceApp extends Application.AppBase {

    //! Constructor
    public function initialize() {
        AppBase.initialize();
    }

    //! Return the initial view for the app
    public function getInitialView() {
        return [new StepDistanceView()];
    }
}

//! Application entry point
function getApp() as Application.AppBase {
    return Application.getApp();
}
