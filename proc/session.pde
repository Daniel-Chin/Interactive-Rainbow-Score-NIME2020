Session session;

class Session {
  ArrayList<CYP> cyps;
  CYP lastCYP = null;
  PImage texture;
  PImage imgArrow;
  static final int TEXTURE_DIAMETER = 4;
  static final float SCALE = .008;
  static final float BUG_FEATURE = .1;  // special effect of dynamic texture

  Session() {
    texture = loadImage("img/cyp_grid.png");
    imgArrow = loadImage("img/arrow.png");
    cyps = new ArrayList<CYP>();
  }

  class CYP extends AbstractNote {
    float _height = METRIC_HEIGHT / 4f;

    int diatone;
    boolean is_rest;
    float x2;
    float y1;
    float _width;
    CYP prev;

    CYP() {
      note_off = -1;
      prev = null;
    }

    int effectiveNoteOff() {
      if (note_off == -1) {
        if (! hapticManager.haptic.progressOnTimeOrSequence()) {
          return note_on + 500;
        } else {
          if (score.time == 0) {
            return note_on + 2000;
          } else {
            return score.time;
          }
        }
      }
      return note_off;
    }

    void draw(RainbowSheet.RainbowBand band) {
      if (is_rest) return;
      float x1 = max(0f, band.time2Ratio(note_on));
      int octave_overflow = 0;
      int normalized_diatone = diatone;
      while (normalized_diatone > MAX_DIATONE) {
        normalized_diatone -= 7;
        octave_overflow = +1;
      }
      while (normalized_diatone < MIN_DIATONE) {
        normalized_diatone += 7;
        octave_overflow = -1;
      }
      float y1 = band.diatoneToY(
        normalized_diatone
      ) - _height / 2f;
      x2 = min(1f, band.time2Ratio(effectiveNoteOff()));
      float _width = x2 - x1;
      if (_width <= 0) {
        return; // not in this rainbowBand
      }
      if (_width > _height * .1) {
        pushMatrix();
        scale(1f / IMG_ALLERGY);   // Processing image() is allergic to floats !?!?!?!?!?!?!?
        int effective_diameter = round(
          TEXTURE_DIAMETER * SCALE * IMG_ALLERGY
        );
        int _x1 = round(x1 * IMG_ALLERGY);
        int _y1 = round(y1 * IMG_ALLERGY);
        int _w = round(_width * IMG_ALLERGY);
        int loop_start = round(
          _height * IMG_ALLERGY
        ) - effective_diameter;
        int loop_end = - round(effective_diameter * .8f);
        if (octave_overflow == 1) {
          loop_start = round(
            _height * IMG_ALLERGY * .8
          );
        } else if (octave_overflow == -1) {
          loop_end = round(
            _height * IMG_ALLERGY * .2
          );
        }
        for (int x = 0; x < _w; x += effective_diameter * band.y_x_ratio) {
          for (
            int y = loop_start; 
            y > loop_end; 
            y -= effective_diameter
          ) {
            image(texture, x + _x1, y + _y1, min((_w - x) * BUG_FEATURE, effective_diameter * band.y_x_ratio), effective_diameter);
          }
        }
        popMatrix();
        pushMatrix();
        translate(0, y1 + _height * .5);
        for (int i = 1; i > -2; i -= 2) {
          if (i != octave_overflow) {
            // do draw
            if (octave_overflow != 0) {
              fill(THEME_LESS_WEAK);
              rect(
                x1, 
                _height * .2, 
                _width, 
                _height * .4
              );
              fill(director.themeFore);
              translate(0, _height * .2);
            }
            rect(
              x1, 
              _height * .4, 
              _width, 
              _height * .2
            );
            
            beginShape();
            vertex(x1, _height * .5);
            vertex(x1, _height * (.5 + .4));
            vertex(x1 + _height * 1 * band.y_x_ratio, _height * .5);
            endShape(CLOSE);
          }

          scale(1, -1);
        }
        popMatrix();
      }
    }

    void drawArrow(RainbowSheet.RainbowBand band, int delta_pitch) {
    //   pushMatrix();
    //   translate(0, levelToY(level));
    //   scale(1f / IMG_ALLERGY);   // Processing image() is allergic to floats !?!?!?!?!?!?!?
    //   float WIDTH = .04;
    //   float _width;
    //   int time;
    //   if (delta_pitch < 0) {
    //     translate(0, _height * IMG_ALLERGY);
    //     scale(1, -1);
    //   }
    //   for (int i = 0; i < 2; i ++) {
    //     if (i == 0) {
    //       time = note_on;
    //       _width = - WIDTH;
    //     } else {
    //       time = effectiveNoteOff();
    //       _width = WIDTH;
    //     }
    //     image(imgArrow, 
    //       int(IMG_ALLERGY * band.time2Ratio(time)),
    //       0, 
    //       int(IMG_ALLERGY * _width),
    //       int(IMG_ALLERGY * _height)
    //     );
    //   }
    //   popMatrix();
    }
  }

  void makeCYP(int pitch, boolean is_rest) {
    CYP cyp = new CYP();
    cyp.is_rest = is_rest;
    cyp.pitch = pitch;
    if (! is_rest) {
      cyp.diatone = pitchToDiatone(cyp.pitch);
    }
    cyp.note_on = score.time;
    if (hapticManager.haptic.progressOnTimeOrSequence()) {
      cyp.note_on -= Parameter.INPUT_LATENCY;
    }
    if (lastCYP != null) {
      lastCYP.note_off = cyp.note_on;
      cyp.prev = lastCYP;
    }
    cyps.add(cyp);
    lastCYP = cyp;
  }

  void printCYPs() {
    for (CYP cyp : cyps) {
      println(cyp.repr());
    }
  }

  void clearCYPsAfter(int time) {
    for (int i = cyps.size() - 1; i >= 0; i --) {
      if (time < cyps.get(i).note_on) {
        cyps.remove(i);
      }
    }
  }
}
