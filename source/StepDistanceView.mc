//
// Step Distance Data Field View
//
// Full-screen layout (height >= 200):
//   [      N  Steps  (centered)   ]
//   [  Distance (left) | Speed (right) ]
//   [    Miles         |    mph        ]
//
// Compact layout (height < 200):
//   [  N Steps (centered, smaller)   ]
//   [  Distance  |    Speed          ]
//   [   Miles    |    mph            ]
//
// Analyzer-safe design notes:
//   - No Boolean members used as branch conditions (analyzer traces init values)
//   - Timer state checked via info.timerState parameter (opaque to analyzer)
//   - ActivityMonitor.getInfo() returns non-nullable Info - no null guard needed
//   - Speed calculation is branchless (+1.0f denominator prevents div/0)
//   - Circular buffer always seeded, no "full" flag needed
//

import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class StepDistanceView extends WatchUi.DataField {

    private const SPEED_BUFFER_SIZE = 15;
    private const CM_PER_MILE       = 160934.4f;

    private var _baselineSteps  as Number;
    private var _baselineDistCm as Number;

    private var _activitySteps as Number;
    private var _distanceMiles as Float;
    private var _speedMph      as Float;

    private var _bufTimestamps as Array<Number>;
    private var _bufDistances  as Array<Number>;
    private var _bufWriteIdx   as Number;

    private var _xCenter      as Number;
    private var _xLeft        as Number;
    private var _xRight       as Number;
    private var _ySteps       as Number;
    private var _yBottomValue as Number;
    private var _yBottomLabel as Number;

    private var _stepsNumFont   as Graphics.FontDefinition;
    private var _stepsLabelFont as Graphics.FontDefinition;
    private var _bottomFont     as Graphics.FontDefinition;

    public function initialize() {
        DataField.initialize();

        _baselineSteps  = 0;
        _baselineDistCm = 0;

        _activitySteps = 0;
        _distanceMiles = 0.0f;
        _speedMph      = 0.0f;

        _bufTimestamps = [] as Array<Number>;
        _bufDistances  = [] as Array<Number>;
        for (var i = 0; i < SPEED_BUFFER_SIZE; i++) {
            _bufTimestamps.add(0);
            _bufDistances.add(0);
        }
        _bufWriteIdx = 0;

        _xCenter      = 0;
        _xLeft        = 0;
        _xRight       = 0;
        _ySteps       = 0;
        _yBottomValue = 0;
        _yBottomLabel = 0;

        _stepsNumFont   = Graphics.FONT_NUMBER_MILD;
        _stepsLabelFont = Graphics.FONT_SMALL;
        _bottomFont     = Graphics.FONT_MEDIUM;
    }

    public function onLayout(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        _xCenter = w / 2;
        _xLeft   = w / 4;
        _xRight  = (w * 3) / 4;

        if (h >= 200) {
            _stepsNumFont   = Graphics.FONT_NUMBER_MILD;
            _stepsLabelFont = Graphics.FONT_SMALL;
            _bottomFont     = Graphics.FONT_MEDIUM;

            _ySteps       = (h * 30) / 100;
            _yBottomValue = (h * 60) / 100;
            _yBottomLabel = (h * 78) / 100;
        } else {
            _stepsNumFont   = Graphics.FONT_SMALL;
            _stepsLabelFont = Graphics.FONT_XTINY;
            _bottomFont     = Graphics.FONT_TINY;

            _ySteps       = (h * 22) / 100;
            _yBottomValue = (h * 58) / 100;
            _yBottomLabel = (h * 80) / 100;
        }
    }

    //! Seed all buffer slots with the given timestamp and zero distance.
    //! After seeding, _bufWriteIdx=0 is both the next write target and the
    //! oldest slot, so no "is full?" flag is ever needed.
    private function seedBuffer(nowMs as Number) as Void {
        for (var i = 0; i < SPEED_BUFFER_SIZE; i++) {
            _bufTimestamps[i] = nowMs;
            _bufDistances[i]  = 0;
        }
        _bufWriteIdx = 0;
    }

    public function onTimerStart() as Void {
        var amInfo = ActivityMonitor.getInfo();
        _baselineSteps  = (amInfo.steps    != null) ? amInfo.steps    : 0;
        _baselineDistCm = (amInfo.distance != null) ? amInfo.distance : 0;
        seedBuffer(System.getTimer());
    }

    public function onTimerResume() as Void {
        seedBuffer(System.getTimer());
    }

    public function onTimerReset() as Void {
        _baselineSteps  = 0;
        _baselineDistCm = 0;
        _activitySteps  = 0;
        _distanceMiles  = 0.0f;
        _speedMph       = 0.0f;
        seedBuffer(0);
    }

    public function compute(info as Activity.Info) as Void {
        // ActivityMonitor.getInfo() returns non-nullable Info — no null guard needed
        var amInfo = ActivityMonitor.getInfo();

        var currentSteps  = _baselineSteps;
        var currentDistCm = _baselineDistCm;
        if (amInfo.steps    != null) { currentSteps  = amInfo.steps;    }
        if (amInfo.distance != null) { currentDistCm = amInfo.distance; }

        var sessionSteps  = currentSteps  - _baselineSteps;
        var sessionDistCm = currentDistCm - _baselineDistCm;
        if (sessionSteps  < 0) { sessionSteps  = 0; }
        if (sessionDistCm < 0) { sessionDistCm = 0; }

        _activitySteps = sessionSteps;
        _distanceMiles = sessionDistCm.toFloat() / CM_PER_MILE;

        // Use info.timerState (from parameter — opaque to static analyzer)
        // instead of a Boolean member which the analyzer traces from initialize()
        if (info.timerState != null && info.timerState == Activity.TIMER_STATE_ON) {
            var nowMs = System.getTimer();

            _bufTimestamps[_bufWriteIdx] = nowMs;
            _bufDistances[_bufWriteIdx]  = sessionDistCm;
            _bufWriteIdx = (_bufWriteIdx + 1) % SPEED_BUFFER_SIZE;

            _speedMph = calculateRollingSpeed(nowMs, sessionDistCm);
        } else {
            _speedMph = 0.0f;
        }
    }

    //! Speed in mph from circular buffer.
    //! Branchless: +1.0f in denominator prevents div/0 (negligible 1ms error over
    //! ~15s window). When buffer is freshly seeded deltaCm=0 so result is 0.0.
    private function calculateRollingSpeed(nowMs as Number, currentDistCm as Number) as Float {
        var oldestIdx = _bufWriteIdx;
        var deltaMs   = nowMs - _bufTimestamps[oldestIdx];
        var deltaCm   = currentDistCm - _bufDistances[oldestIdx];

        return (deltaCm.toFloat() / (deltaMs.toFloat() + 1.0f)) * (3600000.0f / CM_PER_MILE);
    }

    public function onUpdate(dc as Dc) as Void {
        var bgColor = getBackgroundColor();
        var fgColor = Graphics.COLOR_WHITE;
        if (bgColor == Graphics.COLOR_WHITE) {
            fgColor = Graphics.COLOR_BLACK;
        }

        dc.setColor(fgColor, bgColor);
        dc.clear();
        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);

        var numStr   = _activitySteps.format("%d");
        var labelStr = " Steps";
        var numW     = dc.getTextDimensions(numStr,   _stepsNumFont)[0];
        var labelW   = dc.getTextDimensions(labelStr, _stepsLabelFont)[0];
        var startX   = _xCenter - (numW + labelW) / 2;

        dc.drawText(startX,        _ySteps, _stepsNumFont,
                    numStr,   Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(startX + numW, _ySteps, _stepsLabelFont,
                    labelStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.drawText(_xLeft, _yBottomValue, _bottomFont,
                    _distanceMiles.format("%.2f"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(_xLeft, _yBottomLabel, Graphics.FONT_XTINY,
                    "Miles",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.drawText(_xRight, _yBottomValue, _bottomFont,
                    _speedMph.format("%.1f"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(_xRight, _yBottomLabel, Graphics.FONT_XTINY,
                    "mph",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
