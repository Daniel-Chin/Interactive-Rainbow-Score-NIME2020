// this file is in charge of setup, connect, and void draw. 

import java.util.Arrays;
import processing.serial.*;
import processing.sound.*;

final int COM = 0;
// final boolean DEBUGGING_NO_ARDUINO = true;
final boolean DEBUGGING_NO_ARDUINO = false;
// final boolean DEBUGGING_NO_BREATH = true;
final boolean DEBUGGING_NO_BREATH = false;
final boolean CAN_WORKOUT = false;
final int ROUND_ROBIN_PACKET_MAX_SIZE = 127;  // one-byte length indicator maximum 127 on serial

String WHICH; // daniel? demi? ian?
String TITLE;

Port port;
boolean abort = false;
String abort_msg = "ABORT";
PrintWriter generalLogger;

PFont kaiti;

void setup() {
  // size(1366, 768);
  fullScreen();
  noSmooth();
  generalLogger = createWriter(String.format(
    "logs/%02d;%02d;%02d.log", hour(), minute(), second()
  ));
  kaiti = loadFont("KaiTi-18.vlw");
  textFont(kaiti);
  director.global_text_scale = 2.2;
  Arrays.fill(degree_config, 90);
  playback = new Playback();
  session = new Session();
  setupMetronome();
  director.transitionManager.speed = .05f;
  director.themeBack = #ffffff;
  director.themeFore = #000000;
  director.themeWeak = #cccccc;
  director.themeHighlight = #ddffff;
  director.themeHighlightInvert = #005555;
  director.enterScene(new SceneChooseWHICH());
}

void loadConstantsFromFile() {
  String lines[] = loadStrings(WHICH + "/constants.txt");
  String phrases[];
  for (String line : lines) {
    phrases = line.split("=");
    if (phrases.length == 2) {
      // Valid format
      switch (phrases[0]) {
      case "TITLE":
        TITLE = phrases[1];
        break;
      case "Parameter.Hint.slow":
        Parameter.Hint.slow = int(phrases[1]);
        break;
      case "Parameter.Hint.weak":
        Parameter.Hint.weak = int(phrases[1]);
        break;
      default:
        fatalError("Unknown constant: " + phrases[0]);
      }
    }
  }
}

class Port {
  // logs communications
  // fake a dummy interface when DEBUGGING_NO_ARDUINO is false
  // Do the Round Robin for bluetooth
  Serial serial;
  PrintWriter sendLogger;
  PrintWriter recvLogger;
  String outQueue = "";
  String inQueue = "";
  boolean round_robin_my_turn = true;
  int round_robin_recv_state = -1;
  long rtl_start = 0;
  int rtl = 0;
  int proc_q_len = 0;
  int ardu_q_len = 0;

  void initLoggers() {
    sendLogger = createWriter("Serial_proc_ardu.log");
    recvLogger = createWriter("Serial_ardu_proc.log");
  }
  public Port(Serial serial) {
    this.serial = serial;
    initLoggers();
  }
  public Port(String s) {
    assert s.equals("fake");
    initLoggers();
  }
  void loop() {
    if (DEBUGGING_NO_ARDUINO) return;
    if (round_robin_my_turn) {
      // println("proc turn");
      proc_q_len = outQueue.length();
      int packet_size = min(proc_q_len, ROUND_ROBIN_PACKET_MAX_SIZE);
      serial.write(packet_size);
      if (packet_size > 0) {
        serial.write(outQueue.substring(0, packet_size));
        outQueue = outQueue.substring(packet_size);
      }
      rtl_start = millis();
      round_robin_my_turn = false;
      round_robin_recv_state = -2;
    } else {
      // println("ardu turn");
      while (serial.available() > 0) {
        // println("avai");
        if (round_robin_recv_state == -2) {
          assert serial.readChar() == '\n';
          rtl = int(millis() - rtl_start);
          round_robin_recv_state = -1;
        } else if (round_robin_recv_state == -1) {
          round_robin_recv_state = serial.read();
          ardu_q_len = round_robin_recv_state;
        } else {
          // round_robin_recv_state > 0
          inQueue += serial.readChar();
          // println("inQ", inQueue);
          round_robin_recv_state -= 1;
        }
        if (round_robin_recv_state == 0) {
          round_robin_my_turn = true;
          break;
        }
      }
    }
  }
  void write(String s, boolean log_line_break) {
    if (! DEBUGGING_NO_ARDUINO) {
      outQueue += s;
    }
    sendLogger.print(s);
    if (log_line_break) {
      sendLogger.println();
    }
  }
  void write(String s) {
    this.write(s, false);
  }
  char read() {
    if (! DEBUGGING_NO_ARDUINO) {
      char recved = inQueue.charAt(0);
      inQueue = inQueue.substring(1);
      recvLogger.print(recved);
      return recved;
    } else return '_';
  }
  int available() {
    if (! DEBUGGING_NO_ARDUINO) {
      return inQueue.length();
    } else return 0;
  }
  char serial_readOne() {  // blocks until got one char
    while (serial.available() == 0) {
      delay(1);
    }
    return (char) serial.read();
  }
  String readAll() {
    String tmp = inQueue;
    inQueue = "";
    recvLogger.print(tmp);
    return tmp;
  }
  void close() {
    sendLogger.flush();
    sendLogger.close();
    recvLogger.flush();
    recvLogger.close();
  }
}

void draw() {
  if (abort) {
    background(0);
    fill(255);
    textSize(72);
    textAlign(CENTER, CENTER);
    text(abort_msg, 0, 0, width, height);
    return;
  }
  if (arduino != null) {
    if (port != null) {
      port.loop();
    }
    arduino.loop();
  }
  background(255);
  // stroke(0);
  // fill(255);
  director.render();
  if (! DEBUGGING_NO_ARDUINO && port != null) {
    float text_size = 24 * director.global_text_scale;
    textSize(text_size);
    textAlign(LEFT);
    int rtl = int(max(port.rtl, millis() - port.rtl_start));
    if (rtl < 200) {
      fill(director.themeFore);
      rtl = port.rtl;
    } else {
      fill(255, 0, 0);
    }
    text(
      "RTL: " + str(rtl) + "ms", 
      0, 0, 
      text_size * 6, text_size
    );
    if (port.proc_q_len < ROUND_ROBIN_PACKET_MAX_SIZE) {
      fill(director.themeFore);
    } else {
      fill(255, 0, 0);
    }
    text(
      "Out Q: " + str(port.proc_q_len), 
      text_size * 6, 0, 
      text_size * 6, text_size
    );
    if (port.ardu_q_len < ROUND_ROBIN_PACKET_MAX_SIZE) {
      fill(director.themeFore);
    } else {
      fill(255, 0, 0);
    }
    text(
      "In Q: " + str(port.ardu_q_len), 
      text_size * 12, 0, 
      text_size * 6, text_size
    );
  }
  if (midiOut != null) midiOut.draw();
  // if (DEBUGGING_NO_ARDUINO || DEBUGGING_NO_BREATH) {
  //   mouse2mouth();
  // }
}

PApplet getThis() {
  return this;
}

void keyPressed() {
  if (key == '`') {
    log("`");   // leave marker in log
    println("`");
  // } else if (key == ESC) {
    // port.close();
    // key = 0;
    // exit();
  } else if (key == 'w') {
    if (arduino != null) {
      if (CAN_WORKOUT) {
        arduino.workOut();
      }
    }
  } else {
    guiKeyPressed();
  }
}

void exit() {
  generalLogger.flush();
  generalLogger.close();
  if (port != null) {
    port.close();
  }
  if (midiOut != null) {
    midiOut.stop();
  }
  println("cleanup complete!");
  super.exit();
}
