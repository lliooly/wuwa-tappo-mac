// CN 1.0.2 BagAtlasTypeTabs: original travel, squash/stretch and damped settling.
class OriginalTypeTabs {
  constructor(root, onSelect) {
    this.root = root;
    this.buttons = [...root.querySelectorAll('[data-filter]')];
    this.slider = root.querySelector('.filter-slider');
    this.onSelect = onSelect;
    this.selected = 0;
    this.hover = null;
    this.center = 0;
    this.width = 0;
    this.frame = 0;
    this.motion = null;
    this.reduced = matchMedia('(prefers-reduced-motion: reduce)');
    this.buttons.forEach((button, index) => {
      button.addEventListener('mouseenter', () => {
        if (this.hover === index) return;
        this.hover = index; this.move(); this.labels();
      });
      button.addEventListener('click', () => this.select(index));
    });
    this.leave = () => {
      const changed = this.hover !== null;
      this.hover = null;
      if (changed || this.motion) this.move();
      this.labels();
    };
    root.addEventListener('mouseleave', this.leave);
    root.addEventListener('pointerleave', this.leave);
    window.addEventListener('blur', this.leave);
    this.observer = new ResizeObserver(() => this.move(true));
    this.observer.observe(root);
    this.reduced.addEventListener('change', () => this.move(true));
    requestAnimationFrame(() => { this.move(true); this.labels(); });
  }
  select(index) {
    this.selected = index;
    if (this.hover === null) this.move();
    this.labels();
    this.onSelect(this.buttons[index].dataset.filter);
  }
  labels() {
    this.buttons.forEach((button, index) => {
      button.classList.toggle('selected', index === (this.hover ?? this.selected));
      button.setAttribute('aria-selected', String(index === this.selected));
      button.tabIndex = index === this.selected ? 0 : -1;
    });
  }
  cancel() { cancelAnimationFrame(this.frame); this.frame = 0; this.motion = null; }
  place(center, width, sx = 1, sy = 1) {
    width = Math.max(36, width);
    const overshoot = width * Math.max(0, sx - 1) / 2;
    const left = Math.max(-overshoot, Math.min(this.root.clientWidth - width + overshoot, center - width / 2));
    this.center = left + width / 2; this.width = width;
    this.slider.style.width = `${width}px`;
    this.slider.style.transform = `translate3d(${left}px,0,0) scale(${sx},${sy})`;
  }
  move(immediate = false) {
    const target = this.buttons[this.hover ?? this.selected];
    const width = Math.max(36, target.offsetWidth), center = target.offsetLeft + width / 2;
    const fromCenter = this.center, fromWidth = this.width || width, distance = Math.abs(center - fromCenter);
    this.cancel();
    if (immediate || this.reduced.matches || (distance < 0.5 && Math.abs(width - fromWidth) < 0.5)) {
      this.place(center, width); return;
    }
    this.motion = { phase: 'travel', start: performance.now(), fromCenter, fromWidth, center, width,
      travelMs: Math.max(215, Math.min(452, 175 + distance * 0.331)) };
    this.frame = requestAnimationFrame(now => this.tick(now));
  }
  tick(now) {
    const motion = this.motion;
    if (!motion) return;
    if (motion.phase === 'travel') {
      const t = Math.max(0, Math.min(1, (now - motion.start) / motion.travelMs));
      const ease = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
      const stretch = Math.sin(Math.min(1, t / 0.32) * Math.PI / 2);
      const sx = 1 + 0.22 * stretch, sy = 1 - 0.16 * stretch;
      this.place(motion.fromCenter + (motion.center - motion.fromCenter) * ease,
        motion.fromWidth + (motion.width - motion.fromWidth) * ease, sx, sy);
      if (t >= 1) { motion.phase = 'settle'; motion.start = now; motion.sx = sx; motion.sy = sy; }
    } else {
      const t = Math.max(0, Math.min(1, (now - motion.start) / 292));
      const spring = Math.exp(-2.6 * t) * Math.cos(t * Math.PI * 2.75);
      this.place(motion.center, motion.width, 1 + (motion.sx - 1) * spring, 1 - (1 - motion.sy) * spring);
      if (t >= 1) { this.place(motion.center, motion.width); this.motion = null; this.frame = 0; return; }
    }
    this.frame = requestAnimationFrame(now => this.tick(now));
  }
}
