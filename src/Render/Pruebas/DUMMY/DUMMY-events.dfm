object DummyEvents: TDummyEvents
  ClientWidth = 160
  ClientHeight = 100
  OnCreate = DUMMYHandler
  OnShow = DUMMYHandler
  object Timer: TTimer
    Enabled = True
    Interval = 1
    OnTimer = DUMMYHandler
  end
end
