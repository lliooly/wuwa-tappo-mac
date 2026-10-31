// Draw all full transparent canvases in the original 200 CSS px coordinate space.
export function createPetView(container, scale = 1) {
  if (!Number.isFinite(scale) || scale <= 0) throw new Error('缩放必须为正数');
  const stage = document.createElement('div');
  Object.assign(container.style, { width: `${200 * scale}px`, height: `${200 * scale}px` });
  Object.assign(stage.style, {
    position: 'relative', width: '200px', height: '200px',
    transform: `scale(${scale})`, transformOrigin: 'top left', pointerEvents: 'none'
  });
  const images = new Map();
  for (const kind of ['head', 'body', 'accessory']) {
    const img = document.createElement('img');
    img.alt = '';
    img.draggable = false;
    Object.assign(img.style, { position: 'absolute', left: '0', top: '0', width: '200px', height: '200px' });
    stage.append(img);
    images.set(kind, img);
  }
  container.replaceChildren(stage);
  return {
    render(layers) {
      for (const [kind, img] of images) {
        const layer = layers.find(entry => entry.kind === kind);
        img.hidden = !layer;
        if (layer) {
          if (img.getAttribute('src') !== layer.src) img.src = layer.src;
          img.style.transform = `translate(${layer.x}px, ${layer.y}px)`;
        }
      }
    },
    dispose() { stage.remove(); }
  };
}
