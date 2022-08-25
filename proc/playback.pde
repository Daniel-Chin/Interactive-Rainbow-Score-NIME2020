Playback playback = null;

class Playback {
  static final int CYP_MODE = 0;
  static final int TRUTH_MODE = 1;

  long t0;
  int mode;
  boolean paused = false;
  int note_i;
  int entrance_time;
  boolean entering;
  ArrayList<AbstractNote> noteList = new ArrayList<
    AbstractNote
  >(); // compiler be like "may not have been initialized"

  void pause() {
    paused = true;
    arduino.clearSynth(0);
  }
  
  void reload() {
    if (mode == TRUTH_MODE) {
      play(1);
    } else {
      play(2);
    }
  }
  
  void play(int review_mode) {
    paused = false;
    t0 = round(
      millis() - score.time / Parameter.tempoMuliplier()
    ) + Parameter.BLUETOOTH_MIDI_BUF_MS + Parameter.PROC2ARDU_LATENCY;
    updateScoreTimeFromT0();
    if (review_mode == 2) {
      this.mode = CYP_MODE;
    } else {
      this.mode = TRUTH_MODE;
    }
    if (this.mode == CYP_MODE) {
      noteList = new ArrayList<AbstractNote>(session.cyps);
    } else if (this.mode == TRUTH_MODE) {
      noteList = new ArrayList<AbstractNote>(score.notes);
    }
    // seek
    int audio_score_time = getAudio_score_time();
    note_i = 0;
    for (AbstractNote note : noteList) {
      if (note.note_on >= audio_score_time) { 
        break;
      }
      note_i ++;
    }
    note_i --;

    entrance_time = audio_score_time;
    entering = true;
    arduino.syncClock();
  }

  void updateScoreTimeFromT0() {
    score.time = round((millis() - t0) * Parameter.tempoMuliplier());
  }
  int getAudio_score_time() {
    return score.time + round((
      Parameter.BLUETOOTH_MIDI_BUF_MS + Parameter.PROC2ARDU_LATENCY
    ) * Parameter.tempoMuliplier());
  }

  String loop() {
    if (paused) return "paused";
    if (noteList.size() == 0) {
      onEnd();
      return END;
    }
    if (score.time >= noteList.get(
      noteList.size() - 1
    ).note_off) {
      score.time = 0;
      onEnd();
      return END;
    }
    float next_metronome = ceil((
      score.time + Parameter.METRONOME_LATENCY * Parameter.tempoMuliplier()
    ) / score.metronome_time) * score.metronome_time;
    updateScoreTimeFromT0();
    int audio_score_time = getAudio_score_time();
    if (
      score.time + Parameter.METRONOME_LATENCY * 
      Parameter.tempoMuliplier() > next_metronome
    ) {
      metronome(1);
    }

    AbstractNote thisNote = null;
    AbstractNote nextNote = null;
    if (note_i >= 0) {
      thisNote = noteList.get(note_i);
    }
    if (note_i + 1 < noteList.size()) {
      nextNote = noteList.get(note_i + 1);
    }
    if (nextNote == null || audio_score_time < nextNote.note_on) {
      if (thisNote == null) {
        // first note not reached yet
        return "ok";
      }
      if (audio_score_time < thisNote.note_on) {
        fatalError("error qcbotnwcer83");
        return END;
      }
      // still same note
      return "ok";
    } else {
      if (audio_score_time < nextNote.note_off) {
        int last_t;
        if (entering) {
          last_t = entrance_time;
          entering = false;
        } else {
          last_t = thisNote.note_on;
        }
        playOne(nextNote, (
          nextNote.note_on - last_t
        ) / Parameter.tempoMuliplier());
        note_i ++;
        return "ok";
      } else {
        println("Error info:");
        println(nextNote.note_on);
        println(nextNote.note_off);
        fatalError("Probably, multiple notes were encountered in one frame. Lower the tempo? Or maybe your CPU is too slow and timesteping is not fast enough.");
        return END;
      }
    }
  }

  float dither = 0;
  void playOne(AbstractNote note, float f_dt) {
    int dt = int(f_dt);
    dither += f_dt - dt;
    if (dither >= 1) {
      dither -= 1;
      dt += 1;
    }
    if (note.is_rest) {
      arduino.clearSynth(dt);
    } else {
      arduino.synthPitch(note.pitch, dt);
    }
  }

  void onEnd() {
    arduino.clearSynth(0);
  }
}
