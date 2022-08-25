class SceneHandshake extends Layer {
  static final int MAX_RETRY = 5;

  static final String EXPECTING = "hi processing";
  int EXPECT_LEN = EXPECTING.length();

  int retry = 0;
  String port_name;
  int tolerance;
  int n_chars_got;
  boolean started = false;
  boolean did_draw = false;
  boolean did_draw_2 = false;

  String got;
  String sent;
  
  SceneHandshake() {
    super();
    title = "Handshake";
  }
  
  void onEnter() {
    if (DEBUGGING_NO_ARDUINO) {
      port = new Port("fake");
      finish();
    } else {
      String[] ports = Serial.list();
      {
        int i = 0;
        for (String name : ports) {
          println(i, ":", name);
          i ++;
        }
      }
      port_name = ports[COM];
    }
  }
  
  void finish() {
    midiOut = new MidiOut();
    arduino = new Arduino();
    loadDegreeConfig();
    loadDegreeSeizure();
    delay(300);
    director.enterScene(new SceneMain());
  }
  
  void draw() {
    if (DEBUGGING_NO_ARDUINO) return;
    if (retry > MAX_RETRY) {
      fatalError("Handshake failed"); return;
    }
    background(director.themeBack);
    fill(director.themeFore);
    textAlign(CENTER, CENTER);
    textSize(72 * director.global_text_scale);
    text("Please wait...", 0, -.3 * height, width, height);
    textSize(48 * director.global_text_scale);
    text("Connected to " + port_name, 0, -.1 * height, width, height);
    text("Handshaking with Arduino... ", 0, 0 * height, width, height);
    text("Sent: '" + sent + "'.", 0, .1 * height, width, height);
    text("Receiving: '" + got + "'.", 0, .2 * height, width, height);
    text("Retry " + str(retry) + " / " + str(MAX_RETRY), 0, .3 * height, width, height);
    if (! did_draw) {
      did_draw = true;
      background(director.themeBack);
      textSize(72 * director.global_text_scale);
      text("Please wait...", 0, -.3 * height, width, height);
      textSize(48 * director.global_text_scale);
      text("Opening port: " + port_name + "...", 0, -.1 * height, width, height);
      return;
    }
    if (! started) {
      started = true;
      tolerance = 1;
      n_chars_got = 0;
      for (int i = 0; i < 4; i ++) {
        try {
          port = new Port(new Serial(getThis(), port_name, 9600));
          break;
        } catch (Exception e) { // port busy (probably)
          println("Caught exception:", e.getMessage());
        }
      }
      if (port == null) {
        fatalError("Port busy. Check connection.");
        return;
      }
      port.serial.clear();
      port.serial.write("hi arduino");
      sent = "hi arduino";
      got = "";
    }
    if (n_chars_got == EXPECT_LEN) {
      if (did_draw_2) {
        finish();
      } else {
        did_draw_2 = true;
        return;
      }
    } else {
      char recved;
      if (port.serial.available() > 0) {
        recved = (char) port.serial.read();
      } else {
        return;
      }
      got += recved;
      if (recved == EXPECTING.charAt(n_chars_got)) {
        n_chars_got ++;
      } else {
        if (tolerance > 0) {
          tolerance --;
          while (port.serial_readOne() != EXPECTING.charAt(0)) {
            got += '_';
          }
          n_chars_got = 1;
          return;
        }
        String residu = port.readAll();
        residu = residu.substring(0, min(30, residu.length()));
        println("Got '", got + residu, "', which is incorrect.");
        port.serial.clear();
        port.serial.stop();
        retry ++;
        started = false;
        sent = "";
        got = "";
      }
    }
  }
}
