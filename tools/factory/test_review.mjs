// Exercise the generated checkpoint's browser behavior without a browser dependency.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(process.argv[2], 'utf8').split('<script>')[1].split('</script>')[0];
class Element {
  constructor(tag) { this.tagName = tag; this.children = []; this.attributes = {}; this.style = {}; this.value = ''; this.hidden = false; }
  append(...items) { this.children.push(...items); }
  replaceChildren(...items) { this.children = [...items]; }
  setAttribute(key, value) { this.attributes[key] = value; }
  get classList() { return {toggle: (key, on) => {this.attributes[key] = on;}}; }
  click() { if (this.onclick) this.onclick(); }
}
async function exercise(cloud) {
  const ids = Object.fromEntries(['intro','notice','grid','export'].map(id=>[id,new Element('div')]));
  const store = new Map(), writes = [], calls = []; let exported;
  const database = { collection: (name) => {assert.equal(name,'checkpoint');return {onSnapshot: fn=>fn({docs:[]})};},
    doc: path=>({set: async body=>{writes.push({path,body});}}) };
  const context = vm.createContext({
    document: {getElementById:id=>ids[id],createElement:tag=>new Element(tag),activeElement:null},
    window: cloud ? {claude:{use:async name=>{calls.push(name);if(name==='db')return database;if(name==='user')return {isOwner:async()=>true};throw Error('wrong interface');}}} : {},
    localStorage:{getItem:key=>store.get(key),setItem:(key,value)=>store.set(key,value)},
    URL:{createObjectURL:blob=>{exported=blob;return 'blob:checkpoint';},revokeObjectURL:()=>{}},
    Blob, setTimeout: fn=>{fn();}, console
  });
  vm.runInContext(source, context);
  await new Promise(resolve=>setImmediate(resolve));
  assert.ok(ids.grid.children.length);
  const cards = vm.runInContext('cards', context);
  const sid = Object.keys(cards)[0], card = cards[sid];
  assert.equal(card.veto.disabled,false);
  if(card.love.attributes['aria-pressed']==='true')card.love.onclick();
  card.love.onclick();
  assert.equal(card.love.attributes['aria-pressed'],'true');
  card.veto.onclick();
  assert.equal(card.love.attributes['aria-pressed'],'false');
  assert.equal(card.veto.attributes['aria-pressed'],'true');
  card.note.value='A careful note';card.note.oninput();
  await new Promise(resolve=>setImmediate(resolve));
  ids.export.onclick();
  const picks = JSON.parse(await exported.text());
  const pick = picks.find(p=>String(p.slot)===sid);
  assert.equal(pick.note,'A careful note');assert.equal(pick.veto,true);assert.equal(pick.love,false);
  assert.equal(pick.name,card.select.value);assert.ok(pick.at);assert.equal(pick.round,1);
  if(cloud){assert.deepEqual(calls,['db','user']);assert.equal(writes.at(-1).path,'checkpoint/c'+sid);}
  else{assert.equal(store.size,1);assert.ok(card.status.textContent.includes('Saved'));}
}
await exercise(false);
await exercise(true);
console.log('Checkpoint local saving, cloud saving, love/veto, note and export passed.');
