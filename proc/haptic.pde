HapticManager hapticManager = new HapticManager();

class HapticManager {
  Haptic haptic = null;
  Analysis analysis;
  boolean is_playing = false;
  void start() {
    haptic.start();
    analysis = new Analysis();
    is_playing = true;
  }
  String loop() {
    String result = haptic.loop();
    if (result == END) {
      is_playing = false;
    }
    return result;
  }
}

class Haptic {
  int start_time;
  String name;
  int mode_id;

  Haptic() {
    name = "supernatural banana";
    mode_id = -1;
  }
  void start() {
    if (USE_BGM) {
      loadBgm();
      bgm.play();
      println("BGM starts to play...");  ////
    }
    int guide_region_start = guideRegionStart();
    start_time = millis() + int(
      score.prelude * 1.1 / Parameter.tempoMuliplier()
    ) - guide_region_start;
    session.clearCYPsAfter(guide_region_start);
  }
  String loop() { // to call every frame
    return "arbitrary words";
  }
  void onNoteIn(int pitch, boolean is_rest, char[] fingers) {
    if (score.time < guideRegionStart()) {
      return;
    }
    if (hapticManager.analysis == null) {
      return; // song has not started yet
    }
    for (int i = 0; i < 6; i ++) {
      hapticManager.analysis.add(
        "capacitive", i, millis() - start_time, fingers[i]
      );
    }
    log("onNoteIn " + str(pitch));
    session.makeCYP(pitch, is_rest);
  }
  void onPedalSignal(char state) { }
  boolean canPedalPause() {
    return false;
  }
  boolean progressOnTimeOrSequence() {
    return false;
  }
  boolean hasPlayButton() {
    return true;
  }
  void onFingerChange(int finger_i, char state) {
  }
  int guideRegionStart() {
    if (segLoop.is_active) {
      return segLoop.startTime();
    } else {
      return 0;
    }
  }
  int guideRegionEnd() {
    if (segLoop.is_active) {
      return segLoop.endTime();
    } else {
      return score.total_time;
    }
  }
  int guideRegionFirstNote_i() {
    return score.time2Note_i(guideRegionStart(), true, false);
  }
  int guideRegionLastNote_i() {
    return score.time2Note_i(guideRegionEnd(), false, true);
  }
}

class Force extends Haptic {
  boolean do_groundtruth = false;

  Action currentGroundTruth;
  boolean perfect;

  Force(boolean do_groundtruth) {
    name = "Force Mode";
    mode_id = 0;

    this.do_groundtruth = do_groundtruth;
  }
  void start() {
    super.start();
    score.play_head = guideRegionFirstNote_i() - 1;
    perfect = true;
  }
  String loop() {
    // update time, and metronome
    int time = int((millis() - start_time) * Parameter.tempoMuliplier());
    float prev_metronome = floor((time + Parameter.METRONOME_LATENCY) / score.metronome_time) * score.metronome_time;
    if (score.time + Parameter.METRONOME_LATENCY < prev_metronome) {
      int metronome_i = round((score.time + Parameter.METRONOME_LATENCY) / score.metronome_time);
      metronome(metronome_i % score.metronome_per_measure);
    }
    score.time = time;

    // check end
    if (time >= guideRegionEnd()) {
      for (int i = 0; i < 6; i ++) {
        hapticManager.analysis.add(
          "truth", i, millis() - start_time, '-'
        );
      }
      return endSegment();
    }

    // noteOn event via tracking play_head
    boolean changed = false;
    int haptic_time = time + Parameter.PROC2ARDU_LATENCY;
    while (
      score.play_head != score.notes.size() - 1
      && haptic_time >= score.notes.get(score.play_head + 1).note_on
    ) {
      score.play_head ++;
      changed = true;
    }
    if (changed) {
      if (enteredGuideRegion(haptic_time)) {
        Score.Note note = score.notes.get(score.play_head);
        currentGroundTruth = pitchToAction(note.pitch);
        onNoteOn(note);
      }
    }
    if (auto_po_mode != AUTO_MODE_NONE) {
      int note_i = max(0, score.time2Note_i(
        time + Parameter.PROC2ARDU_LATENCY 
        + Parameter.AUTO_PO_LOOKAHEAD, false, true
      ));
      Score.Note note = score.notes.get(note_i);
      handleAutoPO(note);
    }
    return CONTINUE;
  }
  void onNoteOn(Score.Note note) {
    guideNote(note);
    if (do_groundtruth) {
      arduino.syncClock();
      arduino.synthPitch(note.pitch, 0);
    }
  }
  void guideNote(Score.Note note) {
    if (note.is_rest) return;
    println('!', String.valueOf(currentGroundTruth.fingers));
    for (int i = 0; i < 6; i ++) {
      fingerMeetsNoteGuide(
        i, currentGroundTruth.fingers[i], 
        note.note_off - note.note_on
      );
      hapticManager.analysis.add(
        "truth", i, millis() - start_time, currentGroundTruth.fingers[i]
      );
    }
    if (DEBUGGING_NO_BREATH && note.repeated) {
      // help the player when breath detection is not online
      midiOut.pulse();
    }
  }
  boolean fingerMeetsNoteGuide(int finger_i, int int_state, char char_state, int note_duration) {
    arduino.moveServo(finger_i, int_state, 0);
    hapticManager.analysis.add(
      "guidance", finger_i, millis() - start_time, char_state
    );
    return true;
  }
  boolean fingerMeetsNoteGuide(int finger_i, char state, int note_duration) {
   if (state == '^') {
      return fingerMeetsNoteGuide(finger_i, 0, state, note_duration);
    } else if (state == '_') {
      return fingerMeetsNoteGuide(finger_i, 2, state, note_duration);
    } else {
      fatalError("Haptic: fingerMeetsNoteGuide unexpected state");
      return false;
    }
  }
  boolean progressOnTimeOrSequence() {
    return true;
  }
  String endSegment() {
    int end_or_advance_or_rewind = -1;
    if (segLoop.is_active) {
      switch (segLoop.advance_condition) {
        case SegLoop.NEVER:
          end_or_advance_or_rewind = 2;
          break;
        case SegLoop.ALWAYS:
          end_or_advance_or_rewind = 1;
          break;
        case SegLoop.PERFECT:
          if (perfect) {
            end_or_advance_or_rewind = 1;
          } else {
            end_or_advance_or_rewind = 2;
          }
          break;
      }
      if (end_or_advance_or_rewind == 2) {
        switch (segLoop.exit_condition) {
          case SegLoop.NEVER:
            end_or_advance_or_rewind = 2;
            break;
          case SegLoop.ALWAYS:
            end_or_advance_or_rewind = 0;
            break;
          case SegLoop.PERFECT:
            if (perfect) {
              end_or_advance_or_rewind = 0;
            } else {
              end_or_advance_or_rewind = 2;
            }
            break;
        }
      }
      if (segLoop.special_mode == segLoop.ONE_BREATH) {
        if (mode_id == (
          new OneBreathForce(true)
        ).mode_id) {
          // is in force
          end_or_advance_or_rewind = 2;
          long duration = millis() - (
            (OneBreathForce) this
          ).absolute_start_time;
          hapticManager.haptic = new OneBreathSequenceNoHaptic(
            false, duration
          );
          arduino.relax();
          arduino.clearSynth(0);
        } else {
          // is in seq no-haptic
          hapticManager.haptic = new OneBreathForce(true);
        }
      }
    } else {
      end_or_advance_or_rewind = 0;
    }
    switch (end_or_advance_or_rewind) {
      case 0:
        arduino.relax();
        arduino.autoPO(AUTO_MODE_NONE, 60);
        return END;
      case 1:
        if (segLoop.advance()) {
          if (segLoop.special_mode == segLoop.ONE_BREATH) {
            segLoop.extendTillEnd();
          }
          return CONTINUE;
        } else {
          return END;
        }
      case 2:
        hapticManager.haptic.start();
        return CONTINUE;
      default:
        fatalError("349g58hrw");
        return "fatal";
    }
  }
  boolean enteredGuideRegion(int time) {
    return !(
      segLoop.is_active 
      && time < segLoop.startTime()
    );
  }
}

class Hint extends Force {
  static final String LOOKUP = "^-_";
  char[] servo_state = new char[6];
  int[] weak = new int[6];
  Hint(boolean do_groundtruth) {
    super(do_groundtruth);
    name = "Hint Mode";
    mode_id = 1;
  }
  void start() {
    super.start();
    Arrays.fill(servo_state, '-');
    Arrays.fill(weak, Parameter.Hint.weak);
  }
  boolean fingerMeetsNoteGuide(
    int finger_i, int int_state, char char_state, int note_duration
  ) {
    if (doHint(finger_i, int_state)) {
      if (arduino.finger_position[finger_i] != char_state) {
        weak[finger_i] = max(
          0, weak[finger_i] - Parameter.Hint.weak_acc
        );
      }
      if (servo_state[finger_i] != char_state) {
        weak[finger_i] = Parameter.Hint.weak;
      }
      arduino.moveServo(finger_i, int_state, weak[finger_i]);
      servo_state[finger_i] = char_state;
      hapticManager.analysis.add(
        "guidance", finger_i, millis() - start_time, char_state
      );
      return true;
    }
    return false;
  }
  boolean doHint(int finger_i, int state) {
    if (isMistake(finger_i, state)) {
      perfect = false;
    }
    return true; // for adaptive modes to override
  }
  boolean isMistake(int finger_i, int state) {
    return arduino.finger_position[finger_i] != LOOKUP.charAt(state);
  }
}

class TimeStrictAdaptive extends Hint {
  boolean paused = false;
  int pause_start_time;
  boolean current_note_passed = false;

  TimeStrictAdaptive(boolean do_groundtruth) {
    super(do_groundtruth);
    name = "Adaptive Mode\n人跟机器";
    mode_id = 3;
  }
  boolean doHint(int finger_i, int state) {
    if (isMistake(finger_i, state)) {
      perfect = false;
      return true;
    } else {
      return false;
    }
  }
  String loop() {
    if (paused) {
      return CONTINUE;
    }
    String result = super.loop();
    if (
      result == CONTINUE 
      && score.play_head >= guideRegionFirstNote_i()
    ) {
      Score.Note note = score.notes.get(score.play_head);
      if (! current_note_passed && (
        score.time >= note.note_on 
        + Parameter.INPUT_LATENCY * Parameter.tempoMuliplier()
        + Parameter.TimeStrictAdaptive.tolerance
      )) {
        if (enteredGuideRegion(score.time)) {
          guideNote(note);
        }
        current_note_passed = true;
      }
    }
    return result;
  }
  void onNoteOn(Score.Note note) {
    current_note_passed = false;
  }
  void onFingerChange(int finger_i, char state) {
    if (servo_state[finger_i] == state) {
      // 偷偷回正
      arduino.slowDetach(finger_i);
      servo_state[finger_i] = '-';
      hapticManager.analysis.add(
        "guidance", finger_i, millis() - start_time, '-'
      );
      weak[finger_i] = Parameter.Hint.weak;
    }
    if (
      current_note_passed 
      || score.play_head < guideRegionFirstNote_i() || (
        score.time < score.notes.get(score.play_head).note_on
        + Parameter.INPUT_LATENCY 
      )
    ) {
      return;
    }
    boolean all_correct = true;
    for (int i = 0; i < 6; i ++) {
      if (currentGroundTruth.fingers[i] != arduino.finger_position[i]) {
        all_correct = false;
        break;
      }
    }
    if (all_correct) {
      current_note_passed = true;
    }
  }
  void onPedalSignal(char state) {
    paused = state == '_';
    if (state == '_') {
      pause_start_time = millis();
      if (USE_BGM) {
        bgm.pause();  
      }
    } else {
      start_time += millis() - pause_start_time;
      if (USE_BGM) {
        bgm.play();
      }
    }
  }
  boolean canPedalPause() {
    return true;
  }
}

class TimeStrictNoHaptic extends TimeStrictAdaptive {
  TimeStrictNoHaptic(boolean do_groundtruth) {
    super(do_groundtruth);
    name = "No Haptic\n人跟机器";
    mode_id = 2;
  }
  boolean doHint(int finger_i, int state) {
    super.doHint(finger_i, state);
    return false;
  }
}

class SequenceAdaptive extends TimeStrictAdaptive {
  boolean has_notein = false;
  long last_notein_millis = 0;
  boolean is_last_notein_correct;
  boolean did_finger_change;
  char[] last_fingers = new char[6];

  SequenceAdaptive(boolean do_groundtruth) {
    super(do_groundtruth);
    name = "Adaptive Mode\n机器跟人";
    mode_id = 4;
  }
  void start() {
    super.start();
    Arrays.fill(last_fingers, '?');
    if (USE_BGM) {
      bgm.stop();
    }
    score.play_head = guideRegionFirstNote_i();
    readyForNext();
  }
  boolean checkEnd() {
    if (score.play_head > guideRegionLastNote_i()) {
      score.time = guideRegionEnd();
      return true;
    }
    return false;
  }
  String loop() {
    if (checkEnd()) {
      return endSegment();
    }
    score.setTimeToPlayHead();
    if (has_notein) {
      int commit_time;
      if (is_last_notein_correct) {
        commit_time = Parameter.SequenceAdaptive.CORRECT_COMMIT;
      } else {
        commit_time = Parameter.SequenceAdaptive.INCORRECT_COMMIT;
      }
      if (millis() >= last_notein_millis + commit_time) {
        if (is_last_notein_correct) {
          has_notein = false;
          score.play_head ++;
          readyForNext();
        } else {
          if (did_finger_change && doGuideWhenNoteIn()) {
            did_finger_change = false;
            guideNote(score.notes.get(score.play_head));
          }
        }
      }
    }
    return CONTINUE;
  }
  void onNoteIn(int pitch, boolean is_rest, char[] fingers) {
    super.onNoteIn(pitch, is_rest, fingers);
    has_notein = true;
    last_notein_millis = millis();
    did_finger_change |= ! Arrays.equals(
      last_fingers, fingers
    );
    int ground_truth_pitch = score.notes.get(
      score.play_head
    ).pitch;
    Action groundTruth = pitchToAction(ground_truth_pitch);
    is_last_notein_correct = true;
    for (int i = 0; i < 6; i ++) {
      last_fingers[i] = fingers[i];
      if (groundTruth.fingers[i] != fingers[i]) {
        is_last_notein_correct = false;
      }
      hapticManager.analysis.add(
        "truth", i, millis() - start_time, groundTruth.fingers[i]
      );
    }
    is_last_notein_correct &= ground_truth_pitch == pitch;
  }
  void onPedalSignal(char state) {
    return;
  }
  boolean canPedalPause() {
    return false;
  }
  boolean progressOnTimeOrSequence() {
    return false;
  }
  void readyForNext() {
    skipRests();
    if (! checkEnd()) {
      score.setTimeToPlayHead();
      Score.Note note = score.notes.get(score.play_head);
      currentGroundTruth = pitchToAction(
        note.pitch
      );
      handleAutoPO(note);
    }
  }
  void skipRests() {
    score.play_head = max(0, score.play_head);
    while (
      score.play_head <= score.notes.size() - 1 &&
      score.notes.get(score.play_head).is_rest
    ) {
      score.setTimeToPlayHead();
      session.makeCYP(-1, true);
      score.play_head ++;
    }
  }
  boolean doGuideWhenNoteIn() {
    return true;
  }
}

class SequenceNoHaptic extends SequenceAdaptive {
  SequenceNoHaptic(boolean do_groundtruth) {
    super(do_groundtruth);
    name = "No Hapitc\n机器跟人";
    mode_id = 5;
  }
  boolean doHint(int finger, int state) {
    return false;
  }
}

class HelpMe extends SequenceNoHaptic {
  HelpMe(boolean do_groundtruth) {
    super(do_groundtruth);
    name = "Help Me Mode";
    mode_id = 6;
  }
  void onPedalSignal(char state) {
    if (state == '_') {
      guideNote(score.notes.get(score.play_head));
    }
  }
}

class FreePlay extends Haptic {
  FreePlay() {
    name = "Free Play";
    mode_id = 7;
  }
  String loop() { // to call every frame
    return "this line should be unreachable 3948hrg895p42";
  }
  boolean hasPlayButton() {
    return false;
  }
}

class RepeatAfterMe extends SequenceAdaptive {
  boolean just_rested = false;
  long last_rest_note_time;

  RepeatAfterMe(boolean do_groundtruth) {
    super(do_groundtruth);
    name = "Repeat\nafter me";
    mode_id = 8;
  }

  boolean doGuideWhenNoteIn() {
    return false;
  }
  void onNoteIn(int pitch, boolean is_rest, char[] fingers) {
    super.onNoteIn(pitch, is_rest, fingers);
    just_rested = is_rest;
    if (is_rest) {
      last_rest_note_time = millis();
    }
  }
  String loop() {
    if (just_rested && millis() >= (
      last_rest_note_time + Parameter.REST_COMMIT
    )) {
      just_rested = false;
      arduino.syncClock();
      Score.Note note = score.notes.get(score.play_head);
      arduino.synthPitch(note.pitch, 0);
      guideNote(note);
    }
    return super.loop();
  }
}

class OneBreathForce extends Hint {
  boolean just_rested = false;
  long last_rest_note_time;
  long absolute_start_time;

  OneBreathForce(boolean do_groundtruth) {
    super(do_groundtruth);
    name = "One Breath Force";
    mode_id = 9;
    absolute_start_time = millis();
  }
  void onNoteIn(int pitch, boolean is_rest, char[] fingers) {
    super.onNoteIn(pitch, is_rest, fingers);
    just_rested = is_rest;
    if (is_rest) {
      last_rest_note_time = millis();
    }
  }
  String loop() {
    if (just_rested && millis() >= (
      last_rest_note_time + Parameter.REST_COMMIT
    )) {
      just_rested = false;
      if (
        segLoop.is_active 
        && segLoop.special_mode == SegLoop.ONE_BREATH
        && guideRegionStart() + 1000 < score.time
        // 1000: minimum segment duration
      ) {
        segLoop.end_metronome_i = int(
          score.notes.get(
            score.time2Note_i(score.time, true, true)
          ).note_on / score.metronome_time
        ) + 1;
        segLoop.legalize();
      }
    }
    return super.loop();
  }
}

class OneBreathSequenceNoHaptic extends SequenceNoHaptic {
  long deadline;
  OneBreathSequenceNoHaptic(
    boolean do_groundtruth, long duration
  ) {
    super(do_groundtruth);
    name = "One Breath\nSeq No Haptic";
    mode_id = 10;
    deadline = millis() + round(duration * 1.2) + 2000;
  }
  String loop() {
    if (deadline < millis()) {
      perfect = false;
      return endSegment();
    }
    return super.loop();
  }
}
