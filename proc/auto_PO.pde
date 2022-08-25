static final int AUTO_MODE_NONE = 0;
static final int AUTO_MODE_PITCH = 1;
static final int AUTO_MODE_OCTAVE = 2;

int auto_po_mode = AUTO_MODE_NONE;

void handleAutoPO(Score.Note note) {
  if (auto_po_mode != AUTO_MODE_NONE) {
    if (note.is_rest) {
      return;
    }
    if (auto_po_mode == AUTO_MODE_PITCH) {
      arduino.autoPO(auto_po_mode, note.pitch);
    } else {
      arduino.autoPO(auto_po_mode, note.pitch / 12 - 1);
    }
  }
}
