class SceneMain extends Layer {
  static final float RAINBOWSHEET_RATIO = .85;
  RainbowSheet rainbowSheet = null;
  PVector rainbow_sheet_position;
  PVector rainbow_sheet_size;
  int review_mode = 0;  // 0: inactive, 1: truth, 2: cyp, 3: not yet set
  boolean is_review_playing = false;
  class PlayButtonDiv extends Layer {
    static final int NUM_BUTTONS = 8;
    class DivButton extends Button {
      DivButton(int index, String _text) {
        super();
        this._text = _text;
        float unit_height = (height - WINDOW_MARGIN * 2 + ELEMENT_SPACING) / float(NUM_BUTTONS);
        position = new PVector(
          RAINBOWSHEET_RATIO * width + ELEMENT_SPACING, 
          WINDOW_MARGIN + index * unit_height
        );
        _size = new PVector(
          (1f - RAINBOWSHEET_RATIO) * width 
          - ELEMENT_SPACING - WINDOW_MARGIN, 
          unit_height - ELEMENT_SPACING
        );
        fontsize *= 1.6;
      }
    }
    class OnlyShowsWhenSongLoaded extends DivButton {
      OnlyShowsWhenSongLoaded(int index, String _text) {
        super(index, _text);
      }
      boolean isVisible() {
        return score != null && rainbowSheet != null;
      }
    }
    class BtnChooseSong extends DivButton {
      BtnChooseSong(int index, String _text) {
        super(index, _text);
        fontsize *= .85;
      }
      void onClick() {
        director.push(this, new SceneChooseSong());
        session = new Session();
      }
    }
    class BtnPlay extends OnlyShowsWhenSongLoaded {
      BtnPlay(int index, String _text) {
        super(index, _text);
      }
      void onClick() {
        play();
      }
      boolean isVisible() {
        return (
          super.isVisible() 
          && hapticManager.haptic != null
          && hapticManager.haptic.hasPlayButton()
        );
      }
    }
    class BtnHapticMode extends OnlyShowsWhenSongLoaded {
      int saved_fontsize;
      BtnHapticMode(int index, String _text) {
        super(index, _text);
        fontsize *= .85;
        saved_fontsize = fontsize;
      }
      void onClick() {
        director.push(this, new SceneHapticMode());
      }
      void draw() {
        if (hapticManager.haptic == null) {
          _text = "Haptic Mode";
        } else {
          _text = hapticManager.haptic.name;
        }
        fontsize = saved_fontsize;
        if (_text.length() >= 15) {
          fontsize *= .6;
        }
        super.draw();
      }
    }
    class BtnVisualMode extends OnlyShowsWhenSongLoaded {
      BtnVisualMode(int index, String _text) {
        super(index, _text);
        fontsize *= .85;
      }
      void onClick() {
        director.push(this, new SceneVisualMode(this));
      }
    }
    class BtnSegLoop extends OnlyShowsWhenSongLoaded {
      BtnSegLoop(int index) {
        super(index, "Latin coffee");
        fontsize *= .85;
      }
      void onClick() {
        director.push(this, new SceneSegLoop(this));
      }
      void draw() {
        _text = "Seg Loop\n";
        if (segLoop.is_active) {
          _text += "ON";
        } else {
          _text += "OFF";
        }
        super.draw();
      }
    }
    class BtnTransposeAndTempo extends OnlyShowsWhenSongLoaded {
      BtnTransposeAndTempo(int index, String _text) {
        super(index, _text);
        fontsize *= .7;
      }
      void onClick() {
        director.push(this, new SceneTransposeAndTempo(this));
      }
      boolean isVisible() {
        return score != null;
      }
    }
    class BtnRelax extends DivButton {
      final static String TEXT = "Relax";
      BtnRelax(int index) {
        super(index, TEXT);
      }
      void onPress() {
        _text = "Wait...";
      }
      void onClick() {
        arduino.relax();
        midiOut.clear();
        if (! (DEBUGGING_NO_BREATH || DEBUGGING_NO_ARDUINO)) {
          arduino.recalibrateAtmosPressure();
          while (arduino.calibrating_atmos_pressure) {
            delaySafe(33);
            arduino.loop();
          }
        }
        _text = TEXT;
      }
    }
    class BtnConfigure extends DivButton {
      BtnConfigure(int index, String _text) {
        super(index, _text);
        fontsize *= .85;
      }
      void onClick() {
        director.push(this, new SceneConfig(this));
      }
    }
    PlayButtonDiv() {
      this.add(new BtnChooseSong(0, "Choose\nSong"));
      this.add(new BtnPlay(1, "Play"));
      this.add(new BtnHapticMode(2, "speed way"));
      this.add(new BtnVisualMode(3, "Options"));
      this.add(new BtnSegLoop(4));
      this.add(new BtnTransposeAndTempo(5, "Transpose\n& Tempo"));
      this.add(new BtnRelax(6));
      this.add(new BtnConfigure(7, "Configure"));
    }
    String toString() {
      return "PlayButtonDiv" + super.toString();
    }
    boolean isVisible() {
      return (
        (! hapticManager.is_playing) && review_mode == 0
        && ! (
          segLoop != null
          && segLoop.is_active && segLoop.is_setting_AB
        )
      );
    }
  }
  class StopButtonDiv extends Layer {
    static final int STOP_BUTTON_HEIGHT = 200;
    static final int CARD_HEIGHT = 350;
    class BtnTruth extends Button {
      BtnTruth() {
        super("Truth", RAINBOWSHEET_RATIO * width + ELEMENT_SPACING, 
          WINDOW_MARGIN, 
          width * (1f - RAINBOWSHEET_RATIO) - WINDOW_MARGIN 
          - ELEMENT_SPACING, STOP_BUTTON_HEIGHT
        );
        fontsize *= 1.6;
      }
      void onClick() {
        stopPlaying();
        arduino.relax();
        if (USE_BGM) {
          bgm.stop();
        }
        hapticManager.is_playing = false;
        is_review_playing = true;
        session.cyps.clear();
        review_mode = 1;
        score.time = 0;
        playback.play(review_mode);
      }
    }
    class BtnStop extends Button {
      BtnStop() {
        super("Stop", RAINBOWSHEET_RATIO * width + ELEMENT_SPACING, 
          WINDOW_MARGIN + STOP_BUTTON_HEIGHT + ELEMENT_SPACING, 
          width * (1f - RAINBOWSHEET_RATIO) - WINDOW_MARGIN 
          - ELEMENT_SPACING, STOP_BUTTON_HEIGHT
        );
        fontsize *= 1.6;
      }
      void onClick() {
        stopPlaying();
        arduino.relax();
        if (USE_BGM) {
          bgm.stop();
        }
        hapticManager.is_playing = false;
      }
    }
    class CardDoublePedal extends Card {
      CardDoublePedal() {
        super(
          "You can also\ndouble kick\nthe pedal\nto stop the song.", 
          RAINBOWSHEET_RATIO * width + ELEMENT_SPACING, 
          WINDOW_MARGIN + STOP_BUTTON_HEIGHT * 2 + ELEMENT_SPACING * 2, 
          width * (1f - RAINBOWSHEET_RATIO) - WINDOW_MARGIN 
          - ELEMENT_SPACING, CARD_HEIGHT
        );
        fontsize *= .7;
      }
    }
    class CardPedal extends Card {
      CardPedal() {
        super(
          "Hold down the pedal to pause.", 
          RAINBOWSHEET_RATIO * width + ELEMENT_SPACING, 
          WINDOW_MARGIN + STOP_BUTTON_HEIGHT * 2 + CARD_HEIGHT 
          + ELEMENT_SPACING * 3, 
          width * (1f - RAINBOWSHEET_RATIO) - WINDOW_MARGIN 
          - ELEMENT_SPACING, CARD_HEIGHT
        );
        fontsize *= .8;
      }
      boolean isVisible() {
        return hapticManager.haptic.canPedalPause();
      }
    }
    StopButtonDiv() {
      this.add(new BtnTruth());
      this.add(new BtnStop());
      this.add(new CardDoublePedal());
      this.add(new CardPedal());
    }
    String toString() {
      return "StopButtonDiv" + super.toString();
    }
    boolean isVisible() {
      return hapticManager.is_playing && review_mode == 0;
    }
  }
  class ReviewDiv extends Layer {
    float CARD_HEIGHT = height * .15;
    float BUTTON_HEIGHT = height * .1;
    class CardReview extends Card {
      CardReview() {
        super(
          "Review Mode", 
          RAINBOWSHEET_RATIO * width + ELEMENT_SPACING, 
          WINDOW_MARGIN, 
          width * (1f - RAINBOWSHEET_RATIO) - WINDOW_MARGIN 
          - ELEMENT_SPACING, CARD_HEIGHT
        );
        fontsize *= 1.3;
      }
    }
    class BtnPlayback extends RadioButton {
      BtnPlayback() {
        super("Playback", RAINBOWSHEET_RATIO * width + ELEMENT_SPACING, 
          WINDOW_MARGIN + CARD_HEIGHT + ELEMENT_SPACING, 
          width * (1f - RAINBOWSHEET_RATIO) - WINDOW_MARGIN 
          - ELEMENT_SPACING, BUTTON_HEIGHT
        );
        fontsize *= 1.6;
      }
      void onClick() {
        is_review_playing = true;
        review_mode = 2;
        playback.play(review_mode);
      }
      boolean isSelected() {
        return review_mode == 2 && is_review_playing;
      }
    }
    class BtnTruth extends RadioButton {
      BtnTruth() {
        super("Truth", RAINBOWSHEET_RATIO * width + ELEMENT_SPACING, 
          WINDOW_MARGIN + CARD_HEIGHT + ELEMENT_SPACING + BUTTON_HEIGHT + ELEMENT_SPACING, 
          width * (1f - RAINBOWSHEET_RATIO) - WINDOW_MARGIN 
          - ELEMENT_SPACING, BUTTON_HEIGHT
        );
        fontsize *= 1.6;
      }
      void onClick() {
        is_review_playing = true;
        review_mode = 1;
        playback.play(review_mode);
      }
      boolean isSelected() {
        return review_mode == 1 && is_review_playing;
      }
    }
    class BtnPause extends Button {
      BtnPause() {
        super("Pause", RAINBOWSHEET_RATIO * width + ELEMENT_SPACING, 
          WINDOW_MARGIN + CARD_HEIGHT + ELEMENT_SPACING + 
          (BUTTON_HEIGHT + ELEMENT_SPACING) * 2, 
          width * (1f - RAINBOWSHEET_RATIO) - WINDOW_MARGIN 
          - ELEMENT_SPACING, BUTTON_HEIGHT
        );
        fontsize *= 1.6;
      }
      void onClick() {
        is_review_playing = false;
        playback.pause();
      }
      boolean isVisible() {
        return is_review_playing;
      }
    }
    class BtnFinish extends Button {
      BtnFinish() {
        super("Finish", RAINBOWSHEET_RATIO * width + ELEMENT_SPACING, 
          WINDOW_MARGIN + CARD_HEIGHT + ELEMENT_SPACING + 
          (BUTTON_HEIGHT + ELEMENT_SPACING) * 3, 
          width * (1f - RAINBOWSHEET_RATIO) - WINDOW_MARGIN 
          - ELEMENT_SPACING, BUTTON_HEIGHT
        );
        fontsize *= 1.6;
      }
      void onClick() {
        is_review_playing = false;
        review_mode = 0;
        playback.onEnd();
        rainbowSheet.show_discrete = false;
        session = new Session();
      }
    }
    class BtnDiscrete extends Button {
      // will be a radioButton
      BtnDiscrete() {
        super("Wonderful synergy", RAINBOWSHEET_RATIO * width + ELEMENT_SPACING, 
          WINDOW_MARGIN + CARD_HEIGHT + ELEMENT_SPACING + 
          (BUTTON_HEIGHT + ELEMENT_SPACING) * 4, 
          width * (1f - RAINBOWSHEET_RATIO) - WINDOW_MARGIN 
          - ELEMENT_SPACING, BUTTON_HEIGHT
        );
        fontsize *= 1;
        updateText();
      }
      void onClick() {
        new DiscreteMistakeRepr().classify(
          rainbowSheet.rainbows, session.cyps
        );
        // new DiscreteMistakeRepr().debug(rainbowSheet);
        rainbowSheet.show_discrete = ! rainbowSheet.show_discrete;
        updateText();
      }
      void updateText() {
        if (
          rainbowSheet == null 
          || ! rainbowSheet.show_discrete
        ) {
          _text = "Mistake Repr:\nContinuous";
        } else {
          _text = "Mistake Repr:\nDiecrete";
        }
      }
    }
    ReviewDiv() {
      this.add(new CardReview());
      this.add(new BtnPlayback());
      this.add(new BtnTruth());
      this.add(new BtnPause());
      this.add(new BtnFinish());
      this.add(new BtnDiscrete());
    }
    String toString() {
      return "ReviewDiv" + super.toString();
    }
    boolean isVisible() {
      return review_mode != 0;
    }
  }
  class CardWarning extends Card {
    CardWarning() {
      super(
        "catastrophic street", 
        rainbow_sheet_position.x, 
        rainbow_sheet_position.y, 
        rainbow_sheet_size.x, 
        rainbow_sheet_size.y 
      );
    }
    String toString() {
      return "CardWarning";
    }
    boolean isVisible() {
      return score != null && rainbowSheet == null;
    }
    void draw() {
      _text = "Some notes of this song are not diatonic. \nPlease transpose this song. ";
      super.draw();
    }
  }
  SceneMain() {
    super();
    title = TITLE;
    rainbow_sheet_position = new PVector(
      WINDOW_MARGIN, WINDOW_MARGIN
    );
    rainbow_sheet_size = new PVector(
      (RAINBOWSHEET_RATIO * width - WINDOW_MARGIN - ELEMENT_SPACING), 
      height - 2 * WINDOW_MARGIN
    );
    this.add(new PlayButtonDiv());
    this.add(new StopButtonDiv());
    this.add(new CardWarning());
    this.add(new ReviewDiv());
  }
  void onEnter() {
    if (rainbowSheet != null) {
      this.remove(size() - 1);  // somehow remove(layer) and indexOf(layer) act crazily
      rainbowSheet = null;
    }
    if (score != null && isDiatonic()) {
      rainbowSheet = new RainbowSheet(rainbow_sheet_position, rainbow_sheet_size);
      this.add(rainbowSheet);
    }
  }
  void draw() {
    super.draw();
    if (review_mode == 1 || review_mode == 2) {
      if (playback.loop() == END) {
        review_mode = 3;
      }
    }
    if (hapticManager.is_playing) {
      if (hapticManager.loop() == END) {
        stopPlaying();

        // repeated force mode experiment
        // play();
      }
    }
  }
  void stopPlaying() {
    calculateScore();
    hapticManager.analysis.save();
    midiOut.clear();
    if (session.cyps.size() != 0) {
      session.cyps.get(
        session.cyps.size() - 1
      ).note_off = score.total_time;
    }
    if (Parameter.interactive_visual) {
      review_mode = 3;
    }
  }
  void calculateScore() {
    int right_notes = 0;
    int right;
    int wrong;
    int cyp_i = 0;
    Session.CYP cyp;
    if (session.cyps.size() == 0) return;
    for (Score.Note note : score.notes) {
      right = 0; wrong = 0; 
      for (int i = note.note_on; i < note.note_off; i ++) {
        if (
          cyp_i + 1 != session.cyps.size() 
          && session.cyps.get(cyp_i + 1).note_on < i
        ) {
          cyp_i ++;
        }
        cyp = session.cyps.get(cyp_i);
        if (cyp.note_on > i) {
          // blank area
          wrong ++;
          continue;
        }
        if ((cyp.pitch - note.pitch) % 12 == 0) {
          right ++;
        } else {
          wrong ++;
        }
      }
      if (right / float(right + wrong) > .7) {
        right_notes ++;
      }
    }
    print("Score: ");
    print(right_notes);
    print(" correct out of ");
    print(score.notes.size());
    print(" rate: ");
    print(right_notes * 100 / score.notes.size());
    println("%.");
  }

  void play() {
    if (
      segLoop.is_active 
      && segLoop.special_mode == SegLoop.ONE_BREATH
    ) {
      hapticManager.haptic = new OneBreathForce(true);
      segLoop.extendTillEnd();
    }
    hapticManager.start();
    session = new Session();
    arduino.relax();
    // network.noteEvent();   
    // why was `network.noteEvent();` here? Incorrect:
    // it made ada seq-only trigger guidance for the 
    // first note even when the player did not breath in. 
  }
}
