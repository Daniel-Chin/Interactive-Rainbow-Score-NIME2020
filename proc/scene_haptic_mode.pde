// This file is the Choose Haptic Mode scene.

class SceneHapticMode extends Layer {
  static final int N_BUTTONS = 8;
  class ModeButton extends RadioButton {
    ModeButton(int index) {
      super();
      float unit_height = (
        height - 2 * WINDOW_MARGIN + ELEMENT_SPACING
      ) / float(N_BUTTONS);
      position = new PVector(
        WINDOW_MARGIN, WINDOW_MARGIN + index * unit_height
      );
      _size = new PVector(width - 2 * WINDOW_MARGIN, unit_height - ELEMENT_SPACING);
      _text = getName().replace("\n", " ");
      fontsize *= 1.6;
    }
    boolean isSelected() {
      return hapticManager.haptic != null 
        && getName().equals(hapticManager.haptic.name);
    }
    String getName() {
      return newHaptic().name;
    }
    void onClick() {
      hapticManager.haptic = newHaptic();
      director.pop();
    }
    Haptic newHaptic() {
      return new Haptic();
    }
  }
  class BtnForce extends ModeButton {
    BtnForce(int index) {
      super(index);
    }
    Haptic newHaptic() {
      return new Force(false);
    }
  }
  class BtnHint extends ModeButton {
    BtnHint(int index) {
      super(index);
    }
    Haptic newHaptic() {
      return new Hint(false);
    }
  }
  class BtnTimeStrictAdaptive extends ModeButton {
    BtnTimeStrictAdaptive(int index) {
      super(index);
    }
    Haptic newHaptic() {
      return new TimeStrictAdaptive(false);
    }
  }
  class BtnSequenceAdaptive extends ModeButton {
    BtnSequenceAdaptive(int index) {
      super(index);
    }
    Haptic newHaptic() {
      return new SequenceAdaptive(false);
    }
  }
  class BtnTimeStrictNoHaptic extends ModeButton {
    BtnTimeStrictNoHaptic(int index) {
      super(index);
    }
    Haptic newHaptic() {
      return new TimeStrictNoHaptic(false);
    }
  }
  class BtnSequenceNoHaptic extends ModeButton {
    BtnSequenceNoHaptic(int index) {
      super(index);
    }
    Haptic newHaptic() {
      return new SequenceNoHaptic(false);
    }
  }
  class BtnHelpMe extends ModeButton {
    BtnHelpMe(int index) {
      super(index);
    }
    Haptic newHaptic() {
      return new HelpMe(false);
    }
  }
  class BtnFreePlay extends ModeButton {
    BtnFreePlay(int index) {
      super(index);
    }
    Haptic newHaptic() {
      return new FreePlay();
    }
  }
  class BtnRepeatAfterMe extends ModeButton {
    BtnRepeatAfterMe(int index) {
      super(index);
    }
    Haptic newHaptic() {
      return new RepeatAfterMe(false);
    }
  }
  SceneHapticMode() {
    super();
    title = "Choose Haptic Mode";
    this.add(new BtnRepeatAfterMe(0));
    this.add(new BtnHint(1));
    this.add(new BtnTimeStrictAdaptive(2));
    this.add(new BtnSequenceAdaptive(3));
    this.add(new BtnForce(4));
    this.add(new BtnTimeStrictNoHaptic(5));
    this.add(new BtnSequenceNoHaptic(6));
    this.add(new BtnFreePlay(7));
    // this.add(new BtnHelpMe(8));
  }
}
