// Compatibility reference: CN 1.0.2 index-pp8VWaUF.js, Xd/Bl/Ul/Wl/Uc/Vc.
export const ORIGINAL_TIMING = Object.freeze({ clap: 220, blinkEvery: 5000, blink: 250 });

export class PetAnimation {
  constructor({ clock = globalThis, onChange = () => {} } = {}) {
    this.clock = clock;
    this.onChange = onChange;
    this.body = 1;
    this.head = 1;
    this.nextSide = 'left';
    this.keys = new Set();
    this.timers = new Map();
    this.locked = false;
    this.disposed = false;
  }

  get state() { return Object.freeze({ body: this.body, head: this.head }); }

  publish() { this.onChange(this.state); }

  clear(name) {
    if (this.timers.has(name)) this.clock.clearTimeout(this.timers.get(name));
    this.timers.delete(name);
  }

  after(name, delay, callback) {
    this.clear(name);
    this.timers.set(name, this.clock.setTimeout(() => {
      this.timers.delete(name);
      if (!this.disposed) callback();
    }, delay));
  }

  start() {
    if (this.disposed || this.timers.has('blink-cycle')) return;
    this.publish();
    this.scheduleBlink();
  }

  scheduleBlink() {
    this.after('blink-cycle', ORIGINAL_TIMING.blinkEvery, () => {
      this.blink();
      this.scheduleBlink();
    });
  }

  blink() {
    if (this.disposed) return;
    this.head = 2;
    this.publish();
    this.after('blink-reset', ORIGINAL_TIMING.blink, () => {
      this.head = 1;
      this.publish();
    });
  }

  // Network adapters may apply an explicit side without advancing local alternation.
  applySide(side) {
    if (this.disposed) return;
    if (side !== 'left' && side !== 'right') throw new Error(`Invalid side: ${side}`);
    this.body = side === 'left' ? 2 : 3;
    this.publish();
    this.after('clap-reset', ORIGINAL_TIMING.clap, () => this.idle());
  }

  clap() {
    if (this.locked || this.disposed) return null;
    const side = this.nextSide;
    this.nextSide = side === 'left' ? 'right' : 'left';
    this.applySide(side);
    return side;
  }

  idle() {
    if (this.disposed) return;
    this.body = 1;
    this.publish();
    // Original Wl does not cancel the already scheduled 220 ms reset.
  }

  keyDown(key) {
    if (this.disposed || this.keys.has(key)) return null;
    this.keys.add(key); // Original records the key even under force-update lock.
    return this.clap();
  }

  keyUp(key) {
    if (this.disposed) return false;
    const existed = this.keys.delete(key);
    if (!existed || this.locked) return false;
    this.idle(); // Deliberately does not wait for all other keys to be released.
    return true; // Count once on accepted release; persistence belongs elsewhere.
  }

  mouseButton(action) {
    if (this.locked || this.disposed) return null;
    if (action === 'press') return this.clap();
    if (action === 'release') this.idle();
    return null;
  }

  // Adapter recovery for lost releases; no synthetic click count or direction reset.
  resetInput() {
    this.keys.clear();
    this.clear('clap-reset');
    this.idle();
  }

  dispose() {
    for (const name of [...this.timers.keys()]) this.clear(name);
    this.keys.clear();
    this.disposed = true;
  }
}
