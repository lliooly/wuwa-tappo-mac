export function findAppearance(catalog, type, filename) {
  const item = catalog.items.find(entry => entry.type === type && entry.officialFilename === filename);
  if (!item) throw new Error(`素材条目不存在：${type} / ${filename}`);
  return item;
}

export function assetUrl(item, field, baseUrl) {
  const file = item.files[field];
  if (!file?.path) throw new Error(`素材缺少 ${field}：${item.officialFilename}`);
  if (file.path.startsWith('/') || file.path.split('/').includes('..')) throw new Error('素材路径越界');
  return new URL(file.path, baseUrl).href;
}

export function resolveLayers({ character, accessory = null, state, baseUrl, fallbackOffset = {} }) {
  if (character.type !== 'character_skin' || (accessory && accessory.type !== 'accessory')) {
    throw new Error('角色或配件类型不匹配');
  }
  if (![1, 2, 3].includes(state.body) || ![1, 2].includes(state.head)) throw new Error('动作帧无效');
  // Validate the complete skin before displaying it; never substitute atlas/image.
  for (const field of ['body1', 'body2', 'body3', 'head1', 'head2']) assetUrl(character, field, baseUrl);
  const meta = character.assetMetadata;
  const finite = value => Number.isFinite(Number(value)) ? Number(value) : 0;
  const x = finite(meta ? meta.offset_x : fallbackOffset.x);
  const y = finite(meta ? meta.offset_y : fallbackOffset.y);
  return [
    { kind: 'head', src: assetUrl(character, `head${state.head}`, baseUrl), x: 0, y: 0 },
    { kind: 'body', src: assetUrl(character, `body${state.body}`, baseUrl), x: 0, y: 0 },
    ...(accessory ? [{ kind: 'accessory', src: assetUrl(accessory, 'image', baseUrl), x, y }] : [])
  ];
}
