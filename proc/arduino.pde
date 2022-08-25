// This file is a wrapper class of the Arduino board. 

Arduino arduino = null;

class Arduino {
  static final boolean HAS_PEDAL = false;  // if no pedal, there is atmosphere noise
  String buffer = "";
  boolean calibrating_atmos_pressure = false;
  char[] finger_position = new char[6];
  boolean redirect_bang = false;

  Arduino() {
    Arrays.fill(finger_position, '^');
    setCapacitiveThreshold(Parameter.capacitive_threshold);
  }

  // sending
  void writeServoID(int servo_id) {
    if (servo_id < 3) {
      port.write("L");
    } else {
      port.write("R");
      servo_id -= 3;
    }
    port.write(str(servo_id + 2));
  }

  void moveServo(int servo_id, int state, int weak) {
    port.write("S");
    writeServoID(servo_id);
    int degree = degree_config[servo_id + state * 6];
    if (degree < degree_config[servo_id + 1 * 6]) {
      degree += weak;
    } else {
      degree -= weak;
    }
    if (degree_seizure[servo_id][degree]) {
      degree ++;
    }
    // println('S', servo_id, "->", degree);  // DEBUG
    port.write(encodeDegree(degree), true);
  }

  void slowDetach(int servo_id) {
    port.write("D");
    writeServoID(servo_id);
    port.write(encodeDegree(degree_config[servo_id + 1 * 6]));
    port.write("" + encodeDigit(Parameter.Hint.slow), true);
  }

  char encodeDigit(int digit) {
    // look! when digit <= 9, it behaves like str()! 
    int result = digit + (int) '0';
    if (result >= 127) {
      fatalError("encodeDigit() input too large");
      return '!';
    }
    return (char) result;
  }

  int decodeDigit(char c) {
    return (int) c - (int) '0';
  }

  String encodeDegree(int degree) {
    String result = "" + (char)(degree / 127 + 1);
    return result + (char)(degree % 127 + 1);
  }

  int decodePrintable(char a, char b) {
    return 95 * ((int) a - 32) + (int) b - 32;
  }

  void abort() {
    port.write("\rABORT_", true);
  }

  void relax() {
    for (int i = 0; i < 6; i ++) {
      slowDetach(i);
    }
  }

  void setCapacitiveThreshold(int x) {
    port.write("C" + (char)(x), true);
  }

  // receiving
  void loop() {
    buffer += port.readAll();
    int i;
    for (i = 0; i + 3 <= buffer.length(); i += 3) {
      switch (buffer.charAt(i)) {
      case 'F':
        if (redirect_bang) {
          sceneSyncLatency.bang();
          break;
        }
        int finger_i = decodeDigit(buffer.charAt(i + 1));
        finger_position[finger_i] = buffer.charAt(i + 2);
        if (hapticManager.haptic != null && hapticManager.is_playing) {
          hapticManager.haptic.onFingerChange(
            finger_i, finger_position[finger_i]
          );
        }
        log("onFingerChange " + new String(finger_position));
        break;
      case 'P':
        if (HAS_PEDAL) {
          onPedalSignal(buffer.charAt(i + 1));
        }
        break;
      case 'N':
        int pitch = decodePrintable(
          buffer.charAt(i + 1), 
          buffer.charAt(i + 2)
        );
        boolean is_rest = pitch == 129;
        if (hapticManager.is_playing) {
          hapticManager.haptic.onNoteIn(
            pitch, is_rest, finger_position
          );
        }
        if (DO_MIDI_OUT) {
          if (is_rest) {
            midiOut.clear();
          } else {
            midiOut.play(pitch);
          }
        }
        break;
      case 'R':
        calibrating_atmos_pressure = false;
        break;
      case 'E':
        // wait for the entire error msg to send
        // println("got 'E'.");
        for (int _ = 0; _ < 10; _ ++) {
          port.loop();
          delay(50);   
        }
        buffer += port.readAll();
        fatalError("Arduino E message: " + buffer.substring(i + 1));
        return;
      case 'D':
        onDebugMsg("" + buffer.charAt(i+1) + buffer.charAt(i+2));
        break;
      default:
        fatalError("Unknown ardu -> proc header: chr " + str(int(buffer.charAt(i))));
        print("buffer: ");
        println(buffer);
        return;
      }
    }
    buffer = buffer.substring(i, buffer.length());
  }

  void onPedalSignal(char state) {
    if (hapticManager.is_playing) {
      hapticManager.haptic.onPedalSignal(state);
    }
  }

  void recalibrateAtmosPressure() {
    calibrating_atmos_pressure = true;
    port.write("P");
    port.write(encodeDegree(20), true);
  }

  void onDebugMsg(String msg) {
    if (msg.charAt(0) == '\n') {
      print("Debug message from Arduino: ");
    }
    print(msg);
  }

  void syncClock() {
    port.write("Y" + encodeDegree(
      Parameter.BLUETOOTH_MIDI_BUF_MS
    ));
  }

  void synthPitch(int pitch, int dt) {
    if (pitch == 128) {
      fatalError("Trying to send pitch = 128 to ardu. No. 128 is reserved for rest.");
      return;
    }
    port.write("M" + encodeDegree(pitch) + encodeDegree(dt));
  }

  void clearSynth(int dt) {
    port.write("M" + encodeDegree(128) + encodeDegree(dt));
  }

  void autoPO(int mode, int value) {
    port.write("A" + ((char) (mode + 1)) + ((char) value));
  }

  void workOut() {
    port.write("WO");
  }
}

final String KEYS = " vfrji9";
void keyReleased() {
  // if (key == 'c') session.printCYPs();
  if (arduino == null || ! DEBUGGING_NO_ARDUINO) return;
  int key_i = KEYS.indexOf(key);
  boolean is_key = true;
  if (key_i == -1) {
    key_i = KEYS.indexOf(key + 32); // toLowerCase
    if (key_i == -1) {
      is_key = false;
    }
  }
  if (is_key) {
    char state;
    for (int i = 0; i < 6; i ++) {
      if (i < key_i) {
        state = '_';
      } else {
        state = '^';
      }
      // network.onFingerChange(i, state);
    }
    return;
  // } else if (network.redirect_bang) {
  //   sceneSyncLatency.bang();
  }
}

// void mouse2mouth() {
//   if (midiOut == null) return;
//   float y = 1f - mouseY / float(height);
//   network.onPressureChange(round(max(0f, y - .1) * 200));
// }
