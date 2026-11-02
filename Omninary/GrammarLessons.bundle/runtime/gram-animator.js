/* Professor Gram — full-body geometric character. No network dependencies. */
(function (scope) {
  'use strict';
  const rows = { explain: 0, point: 1, wink: 2, blink: 3 };
  function mouthAt(level, speaking) {
    if (!speaking || !Number.isFinite(level) || level < 0.055) return 0;
    return level < 0.22 ? 1 : level < 0.58 ? 2 : 3;
  }
  function gestureAt(time, cues) {
    let gesture = 'explain';
    for (const cue of cues || []) {
      if (time < cue.at) break;
      if (Object.hasOwn(rows, cue.gesture)) gesture = cue.gesture;
    }
    return gesture;
  }
  function frameAt({ time = 0, level = 0, playing = false, cues = [], override = null, reduced = false }) {
    time = Math.max(0, Number.isFinite(time) ? time : 0);
    let gesture = override || (reduced ? 'explain' : gestureAt(time, cues));
    if (!override && !reduced && playing && gesture === 'explain' && time % 4.2 >= 3.84 && time % 4.2 < 3.99) gesture = 'blink';
    return (rows[gesture] ?? 0) * 4 + mouthAt(level, playing);
  }
  class Animator {
    constructor({ canvas, atlas, audio, chapters, reducedMotion = false }) {
      if (!canvas || !audio || !atlas) throw new Error('Professor Gram needs canvas, atlas, and audio.');
      this.canvas = canvas; this.audio = audio; this.chapters = chapters || [];
      this.reduced = reducedMotion; this.chapter = 0; this.override = null;
      this.animation = 0; this.lastFrame = -1; this.destroyed = false;
      this.context = canvas.getContext('2d');
      this.image = new Image(); this.image.onload = () => this.refresh(); this.image.src = atlas;
      this.events = ['play', 'playing', 'canplay', 'waiting', 'pause', 'ended', 'seeked', 'seeking', 'ratechange', 'loadedmetadata'];
      this.onMedia = () => this.refresh();
      this.events.forEach(name => audio.addEventListener(name, this.onMedia));
      this.onVisibility = () => { if (document.hidden) { cancelAnimationFrame(this.animation); this.animation = 0; } else this.refresh(); };
      document.addEventListener('visibilitychange', this.onVisibility);
      canvas.width = 512; canvas.height = 768;
    }
    setChapter(index) {
      this.chapter = Math.max(0, Math.min(this.chapters.length - 1, index));
      this.override = null; this.lastFrame = -1; this.refresh();
    }
    perform(gesture, duration = 1200) {
      if (!Object.hasOwn(rows, gesture)) return;
      this.override = { gesture, until: performance.now() + Math.max(100, duration) };
      this.refresh();
    }
    cancelGesture() { this.override = null; this.refresh(); }
    refresh() {
      if (this.destroyed) return;
      cancelAnimationFrame(this.animation); this.animation = 0;
      this.update();
    }
    update() {
      if (this.destroyed || document.hidden) return;
      if (this.override && performance.now() >= this.override.until) this.override = null;
      const chapter = this.chapters[this.chapter] || {};
      // Sample on the audio clock. Seeking and speed changes keep the same pose.
      const time = this.audio.currentTime || 0;
      const speaking = !this.audio.paused && !this.audio.ended && this.audio.readyState >= 2;
      const hz = chapter.envelopeHz || 20;
      const sampleIndex = Math.floor(time * hz);
      const level = (chapter.levels?.[sampleIndex] || 0) / 255;
      const frame = frameAt({ time, level, playing: speaking, cues: chapter.gestures,
        override: this.override?.gesture || null, reduced: this.reduced });
      this.draw(frame);
      this.canvas.dataset.mouth = String(frame % 4);
      this.canvas.dataset.gesture = Object.keys(rows)[Math.floor(frame / 4)];
      this.canvas.dataset.speaking = String(speaking);
      if (speaking || this.override) this.animation = requestAnimationFrame(() => this.update());
    }
    draw(frame) {
      if (this.lastFrame === frame || !this.image.complete || !this.image.naturalWidth) return;
      const c = this.context, w = this.image.naturalWidth / 4, h = this.image.naturalHeight / 4;
      c.imageSmoothingEnabled = true; c.imageSmoothingQuality = 'high';
      c.clearRect(0, 0, this.canvas.width, this.canvas.height);
      c.drawImage(this.image, (frame % 4) * w, Math.floor(frame / 4) * h, w, h, 0, 0, this.canvas.width, this.canvas.height);
      this.lastFrame = frame; this.canvas.dataset.frame = String(frame);
    }
    destroy() {
      this.destroyed = true; cancelAnimationFrame(this.animation);
      this.events.forEach(name => this.audio.removeEventListener(name, this.onMedia));
      document.removeEventListener('visibilitychange', this.onVisibility);
      this.image.onload = null;
    }
  }
  const api = { Animator, frameAt, mouthAt, gestureAt };
  scope.ProfessorGram = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(globalThis);
