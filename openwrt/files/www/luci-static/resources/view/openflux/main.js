'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require poll';
'require ui';
'require rpc';

var domainFile = '/etc/openflux/direct-domains.txt';
var commitOpenflux = rpc.declare({ object: 'uci', method: 'commit', params: ['config'], reject: true });

function validateDomainFile(value) {
 if (new TextEncoder().encode(value).length > 262144) throw new Error('Список должен быть не больше 256 КБ');
 var seen = new Set();
 value.replace(/^\uFEFF/, '').split(/\r?\n/).forEach(function(line, index) {
  line = line.trim();
  if (!line || line.startsWith('#')) return;
  var d = line.toLowerCase().replace(/^\*\./, '').replace(/\.$/, '');
  if (d.length > 253 || !d.includes('.') || /^\d+\.\d+\.\d+\.\d+$/.test(d) || !d.split('.').every(function(x) { return /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(x); }))
   throw new Error('Строка ' + (index + 1) + ': нужен домен без https://, пути и пробелов');
  seen.add(d);
 });
 if (seen.size > 10000) throw new Error('Не больше 10000 доменов');
 return seen.size;
}

return view.extend({
 // Commit this app only; unrelated LuCI rollback transactions stay untouched.
 applyConfig: function() {
  if (this._applyPromise) return this._applyPromise;
  var self = this;
  this._applyPromise = commitOpenflux('openflux').finally(function() { self._applyPromise = null; });
  return this._applyPromise;
 },
 load: async function() {
  await uci.load('openflux');
  var text = await fs.read(domainFile).catch(function() { return ''; });
  var problem = '';
  try {
   var check = await fs.exec('/usr/libexec/openflux-network', ['check']);
   if (check.code) problem = (check.stderr || check.stdout || 'Проверьте настройки подключения').slice(0,600);
  } catch(e) { problem = 'Не удалось проверить готовность подключения: ' + e.message; }
  return { domains: text, problem: problem };
 },
 saveDomains: async function() {
  var text = this.domainEditor.value.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
  var count = validateDomainFile(text);
  if (text && !text.endsWith('\n')) text += '\n';
  await fs.write(domainFile, text, 384);
  this.domainEditor.value = text;
  this.domainNotice.textContent = 'Файл сохранён. Доменов: ' + count + '. Изменения вступят в силу при следующем подключении или применении настроек.';
 },
 render: function(data) {
  var self = this;
  var domainText = data.domains;
  self.connectionError = data.problem;
  var m = new form.Map('openflux', '', '');
  var s = m.section(form.NamedSection, 'main', 'openflux');
  s.anonymous = true;
  var o = s.option(form.Value, 'link', 'Личная ссылка подключения');
  o.password = true; o.rmempty = false;
  o.placeholder = 'https://openfluxvpn.ru/s/… или csqtt://connect?…';
  o.description = 'Ссылка хранится только на вашем роутере.';
  o.validate = function(section, value) {
   if (!value) return 'Вставьте ссылку OpenFlux';
   value=value.trim(); return (/^csqtt:\/\/connect\?/.test(value) && value.length <= 8000) || /^https:\/\/openfluxvpn\.ru\/s\/[A-Za-z0-9_-]{22}$/.test(value) ? true : 'Вставьте короткую ссылку OpenFlux или csqtt://connect?…';
  };
  o = s.option(form.Flag, 'enabled', 'Подключаться автоматически');
  o.default = '0'; o.rmempty = false;
  o = s.option(form.ListValue, 'workers', 'Параллельные каналы');
  o.value('2','2 — экономный'); o.value('4','4'); o.value('8','8 — стандартный'); o.value('12','12'); o.value('18','18 — максимум'); o.default='8';
  o.description='Больше каналов может повысить скорость. Результат зависит от реле и сети.';
  var logBox=E('pre',{'style':'white-space:pre-wrap;overflow-wrap:anywhere;max-height:360px;overflow:auto;color:#ddd;font:12px/1.6 monospace'},'Загрузка журнала…');
  var logText='';
  async function refreshLog(){try{var r=await fs.exec('/usr/libexec/openflux-network',['logs']);logText=r.stdout||'Журнал пока пуст';logBox.textContent=logText;}catch(e){logBox.textContent='Не удалось прочитать журнал: '+e.message;}}
  var logs=E('div',{'class':'of-card'},[E('p',{'class':'of-note'},'Последние события подключения. Личные ссылки и ключи скрыты. Журнал хранится в памяти роутера и ограничен по размеру.'),E('div',{'class':'of-file-actions'},[
   E('button',{'type':'button','class':'of-file-secondary','click':refreshLog},'Обновить'),
   E('button',{'type':'button','class':'of-file-secondary','click':function(){var u=URL.createObjectURL(new Blob([logText],{type:'text/plain;charset=utf-8'}));E('a',{href:u,download:'OpenFlux-router-log.txt'}).click();setTimeout(function(){URL.revokeObjectURL(u);},1000);}},'Скачать журнал')]),logBox]);
  refreshLog();
  self.domainEditor = E('textarea', { 'id':'openflux-domains-file', 'rows':12, 'spellcheck':'false', 'aria-label':'Файл доменов для прямого доступа', 'placeholder':'example.org\nexample.net\n# Мой комментарий' }, domainText);
  self.domainNotice = E('p', {'class':'of-note','role':'status'}, 'Один домен на строку. Можно вставить весь список сразу. Поддомены учитываются автоматически.');
  var domainSave = E('button', {'class':'of-file-save','type':'button','click':async function() {
   domainSave.disabled = true;
   try { await self.saveDomains(); }
   catch(e) { ui.addNotification(null,E('p',{},e.message),'error'); }
   finally { domainSave.disabled = false; }
  }}, 'Сохранить файл доменов');
  var importName = E('span', {'class':'of-note','role':'status'}, '');
  var domainImport = E('input', {'type':'file','hidden':'hidden','style':'display:none','accept':'.txt,text/plain','aria-label':'Файл списка доменов','change':async function(ev) {
   var f = ev.target.files[0]; if (!f) return;
   try {
    if (f.size > 262144) throw new Error('Файл должен быть не больше 256 КБ');
    var text = await f.text(); var n = validateDomainFile(text);
    self.domainEditor.value = text;
    importName.textContent = f.name;
    self.domainNotice.textContent = 'Загружено доменов: '+n+'. Проверьте список и нажмите «Сохранить файл доменов».';
   } catch(e) { ui.addNotification(null,E('p',{},e.message),'error'); }
   ev.target.value = '';
  }});
  var importButton = E('button', {'type':'button','class':'of-file-secondary','click':function() { domainImport.click(); }}, 'Загрузить TXT ↑');
  var domainDownload = E('button',{'type':'button','class':'of-file-secondary','click':function() {
   var url=URL.createObjectURL(new Blob([self.domainEditor.value],{type:'text/plain;charset=utf-8'}));
   var a=E('a',{href:url,download:'openflux-direct-domains.txt'}); a.click(); setTimeout(function(){URL.revokeObjectURL(url);},1000);
  }},'Скачать TXT');
  var status = E('div', { 'class': 'of-status' }, 'Проверяем подключение…');
  var connectionNote = E('p', { 'class':'of-muted', 'role':'status' }, self.connectionError || 'При обрыве VPN интернет временно идёт напрямую.');
  self.connectionNote = connectionNote;
  var metrics = E('div', {'class':'of-metrics'});
  var previous = null;
  var traffic = E('div', { 'class': 'of-traffic' }, '↓ 0 МБ     ↑ 0 МБ');
  var busy = false;
  var btn = E('button', { 'class': 'of-power', 'type': 'button', 'aria-label': 'Подключить OpenFlux', 'click': async function() {
   if (busy) return; busy = true; btn.disabled = true;
   try {
    var enabled = !!self.connectionActive;
    if (enabled) {
     uci.set('openflux', 'main', 'enabled', '0');
     await uci.save(); await self.applyConfig();
     var stopResult = await fs.exec('/etc/init.d/openflux', ['stop']);
     if (stopResult.code) throw new Error('Не удалось остановить службу');
    } else {
     await self.saveDomains(); await m.save();
     await self.applyConfig();
     var check = await fs.exec('/usr/libexec/openflux-network', ['check']);
     if (check.code) throw new Error((check.stderr || check.stdout || 'Не удалось проверить настройки подключения').slice(0,600));
     uci.set('openflux', 'main', 'enabled', '1');
     await uci.save(); await self.applyConfig();
     var result = await fs.exec('/etc/init.d/openflux', ['restart']);
     if (result.code) throw new Error((result.stderr || result.stdout || 'Проверьте ссылку и основной маршрут WAN').slice(0, 600));
    }
    window.location.reload();
   } catch(e) { self.connectionError = e.message; connectionNote.textContent = e.message; ui.addNotification(null, E('p', {}, e.message), 'error'); }
   finally { busy = false; btn.disabled = false; }
  } }, '⏻');
  function section(n, text) { return E('div', { 'class': 'of-section' }, [E('span', {}, n), E('strong', {}, text), E('i')]); }
  self.map = m;
  return m.render().then(function(formNode) {
   var root = E('div', { 'class': 'of-root' }, [
    E('style', {}, '.of-root{background:#090909;color:#f5f5f5;padding:clamp(18px,4vw,44px);border-radius:26px;font-family:Arial,sans-serif;max-width:1100px;margin:12px auto}.of-brand{font-size:22px;font-weight:900;letter-spacing:4px}.of-brand b{color:#ff8721}.of-kicker{color:#ff9224;font-size:11px;font-weight:800;letter-spacing:3px;margin-top:40px}.of-root h2{color:#fff;font-size:clamp(28px,4vw,44px);line-height:1.1;margin:14px 0}.of-muted{color:#a9a3a5;line-height:1.65}.of-section{display:flex;align-items:center;gap:14px;margin:30px 0 16px;color:#ff982c;font-size:12px;letter-spacing:2px}.of-section span{border:1px solid #7f4b24;border-radius:12px;padding:12px;letter-spacing:0}.of-section i{height:1px;flex:1;background:linear-gradient(90deg,#80511f,transparent)}.of-card{border:1px solid #483c3b;border-radius:24px;background:linear-gradient(130deg,#231f20,#131313);padding:clamp(20px,3vw,32px)}.of-connect{text-align:center}.of-power{display:block;width:150px;height:150px;border:2px solid #78502e;border-radius:50%;margin:22px auto;background:#111;color:#ff9224;font-size:64px;cursor:pointer;line-height:1}.of-power.active{border-color:#ff9224;box-shadow:0 0 34px #ff79183d;color:white}.of-power:disabled{opacity:.45}.of-metrics{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px;margin-top:24px}.of-metric{background:#111;border:1px solid #45352b;border-radius:14px;padding:14px}.of-metric small{display:block;color:#aaa;margin-bottom:8px}.of-metric strong{color:#ff982c;font-size:19px}.of-status{font-size:20px;font-weight:800;margin:15px 0}.of-traffic{color:#b6adb0;white-space:pre-wrap}.of-root .cbi-map,.of-root .cbi-section{background:transparent;border:0;box-shadow:none;color:#eee}.of-root .cbi-value-title,.of-root label{color:#ddd}.of-root input,.of-root select,.of-root .cbi-dynlist>.item>span{background:#101011!important;color:#f5f5f5!important;border:1px solid #504344!important;border-radius:10px!important}.of-root .cbi-value-description{color:#aaa}.of-root .cbi-map-descr:empty{display:none}.of-root .cbi-value{padding:12px 0}.of-root .cbi-section-node{padding:0}.of-note{font-size:13px;line-height:1.7;color:#b8afb1}.of-footer{margin-top:28px;color:#766d70;font-size:12px}@media(max-width:600px){.of-root{padding:18px}.of-root .cbi-value-title{float:none;width:auto;text-align:left}.of-root .cbi-value-field{margin-left:0}}'),
    E('style', {}, '.of-root .cbi-value-title,.of-root label{color:#ded9db!important}.of-root .cbi-dynlist>.item{background:#101011!important;color:#fff!important;border:1px solid #504344!important;border-radius:10px!important}.of-root .cbi-dynlist>.item>span{border:0!important}.of-root .cbi-dynlist>.item::after,.of-root .btn,.of-root .cbi-button{background:#292225!important;color:#ff9b3b!important;border-color:#5c4640!important}.of-root .cbi-value-field{max-width:660px}.of-root .cbi-input-text{min-width:240px;width:100%}.of-root~.cbi-page-actions{background:#161314;border:1px solid #483c3b;border-radius:18px;padding:18px}.of-root~.cbi-page-actions .cbi-button-apply{background:linear-gradient(110deg,#ff591c,#ff9924);color:white;border:0}.of-root .cbi-value-description{color:#bbb!important}'),
    E('div', { 'class': 'of-brand' }, [E('b', {}, '● '), 'OPENFLUX']),
    E('div', { 'class': 'of-kicker' }, 'ТВОЯ СЕТЬ · ТВОИ ПРАВИЛА'),
    E('h2', {}, 'OpenFlux. На твоём роутере.'),
    E('p', { 'class': 'of-muted' }, 'Одно подключение для устройств домашней сети.'),
    section('01', 'ПОДКЛЮЧЕНИЕ'),
    E('div', { 'class': 'of-card of-connect' }, [traffic, btn, status, connectionNote, metrics]),
    E('style',{},'.of-root #openflux-domains-file{display:block;box-sizing:border-box;width:100%;max-width:none;min-height:270px;padding:18px;margin:18px 0;color:#eee;background:#0d0d0e;border:1px solid #5a4640;border-radius:14px;resize:vertical;font:15px/1.7 monospace}.of-root .of-file-save,.of-root .of-file-secondary{padding:13px 20px;border-radius:12px;font-weight:700;cursor:pointer}.of-root .of-file-save{background:linear-gradient(110deg,#ff591c,#ff9924);color:white;border:1px solid #ff9933}.of-root .of-file-secondary{background:#292225;color:#eee;border:1px solid #5c4640}.of-file-actions{display:flex;flex-wrap:wrap;gap:12px;align-items:center}.of-root h3{color:#fff}'),
    section('02', 'НАСТРОЙКИ'),
    E('div', { 'class': 'of-card' }, [formNode]),
    section('03', 'САЙТЫ НАПРЯМУЮ'),
    E('div',{'class':'of-card'},[E('h3',{},'Один файл. Весь список.'),self.domainNotice,self.domainEditor,E('div',{'class':'of-file-actions'},[domainSave,domainDownload,importButton,domainImport,importName]),E('p',{'class':'of-note'},'Файл: '+domainFile+' · Комментарии начинаются с #. Сохранение файла не переключает текущий VPN.')]),
    section('04', 'ПОДПИСКА'),
    E('div', {'class':'of-card'}, [E('h3',{},'Продолжайте пользоваться OpenFlux'),E('p',{'class':'of-muted'},'Оформите или продлите доступ на сайте. Актуальная цена и акции — на странице оплаты.'),E('a',{'href':'https://openfluxvpn.ru/checkout','target':'_blank','rel':'noopener noreferrer','class':'of-file-save','style':'display:block;text-align:center;text-decoration:none;box-sizing:border-box'},'Оплатить подписку →')]),
    section('05', 'ЖУРНАЛ ПОДКЛЮЧЕНИЯ'),
    logs,
    section('06', 'КАК ЭТО РАБОТАЕТ'),
    E('div', { 'class': 'of-card of-note' }, 'Для списка исключений устройства должны использовать DNS роутера. Защищённый DNS в браузере может обходить этот список. Адреса общих CDN могут использоваться несколькими сайтами. VPN передаёт IPv4; во время подключения публичный IPv6 вне исключений блокируется, чтобы приложения перешли на IPv4. При обрыве прямой IPv6 снова доступен.'),
    E('div', { 'class': 'of-footer' }, 'OpenFlux для OpenWrt · 0.1.2')
   ]);
   async function refreshStatus() {
    try {
     var r = await fs.exec('/usr/libexec/openflux-network',['status']);
     if (r.code) throw new Error('status');
     var x = JSON.parse(r.stdout);
    } catch(e) {
     status.textContent='СТАТУС НЕДОСТУПЕН';
     connectionNote.textContent='Нет ответа от роутера. Повторяем проверку…';
     btn.classList.remove('active'); btn.disabled=true; previous=null;
     return;
    }
    btn.disabled=busy;
    var fresh = Number.isFinite(x.age) && x.age >= 0 && x.age < (x.state === 'connecting' ? 90 : 25);
    var running = x.running === true;
    self.connectionActive=running;
    var state = running ? (fresh ? x.state : 'stale') : (x.state === 'error' ? 'error' : 'stopped');
    var labels = { connected:'ПОДКЛЮЧЕНО', connecting:'ПОДКЛЮЧАЕМСЯ', reconnecting:'ВОССТАНАВЛИВАЕМ VPN', direct:'VPN ПОКА НЕ ПЕРЕДАЁТ ДАННЫЕ', stopped:'OPENFLUX ОТКЛЮЧЁН', error:'ОШИБКА ЗАПУСКА', stale:'НЕТ СВЕЖИХ ДАННЫХ' };
    status.textContent=labels[state] || 'ПРОВЕРЯЕМ ПОДКЛЮЧЕНИЕ';
    btn.classList.toggle('active', state === 'connected');
    btn.setAttribute('aria-label', running ? 'Отключить OpenFlux' : 'Подключить OpenFlux');
    var baseRoute = !x.route_device ? 'Основной маршрут недоступен.' : x.route_device === x.wan_device ? 'Основной маршрут — напрямую через провайдера.' : 'Основной маршрут — через другое подключение ('+x.route_device+').';
    var notes = { connected:'OpenFlux передаёт трафик домашней сети. Исключения используют основной маршрут.', connecting:'Устанавливаем соединение. Ожидаем ответ VPN-сервера.', reconnecting:'Соединение прервалось. Клиент пробует подключиться снова.', direct:'Каналы открыты, но проверка передачи данных пока не проходит.', stale:'Служба запущена, но данные не обновляются. Можно отключить её кнопкой выше.', stopped:'Трафик через OpenFlux сейчас не идёт.', error:x.last_error || 'Не удалось запустить клиент. Подробности в журнале ниже.' };
    connectionNote.textContent=(notes[state] || '')+' '+baseRoute;
    if (!running && x.route_device && x.route_device !== x.wan_device) connectionNote.textContent += ' Для запуска OpenFlux сначала отключите другое VPN-подключение.';
    var dt=previous && x.uptime>previous.uptime && x.elapsed>=previous.elapsed ? x.uptime-previous.uptime : 0;
    var down=dt && fresh && running ? Math.max(0,(x.rx-previous.rx)*8/dt/1000000) : 0;
    var up=dt && fresh && running ? Math.max(0,(x.tx-previous.tx)*8/dt/1000000) : 0;
    var duration=Number(x.elapsed)||0;
    var rows=[['Скорость ↓ / ↑',running && fresh && dt ? down.toFixed(2)+' / '+up.toFixed(2)+' Мбит/с' : '—'],['Каналы', running && fresh ? (x.ready||0)+' / '+(x.workers||x.configured_workers||8) : '0 / '+(x.configured_workers||8)],['Время работы',running && fresh ? Math.floor(duration/3600)+' ч '+Math.floor(duration%3600/60)+' мин' : '—'],['Перезапуски каналов',running && fresh ? String(x.restarts||0) : '—']];
    metrics.replaceChildren.apply(metrics,rows.map(function(pair){return E('div',{'class':'of-metric'},[E('small',{},pair[0]),E('strong',{},pair[1])]);}));
    traffic.textContent='Трафик OpenFlux: ↓ '+((x.rx||0)/1048576).toFixed(1)+' МБ     ↑ '+((x.tx||0)/1048576).toFixed(1)+' МБ';
    previous=x;
    await refreshLog();
   }
   btn.disabled=true;
   refreshStatus();
   poll.add(refreshStatus, 5);
   return root;
  });
 },
 handleSaveApply: async function() {
  await this.saveDomains(); await this.map.save(); await this.applyConfig();
  if (uci.get('openflux','main','enabled') === '1') {
   var check = await fs.exec('/usr/libexec/openflux-network', ['check']);
   if (check.code) { this.connectionError = (check.stderr || check.stdout).slice(0,600); this.connectionNote.textContent = this.connectionError; ui.addNotification(null,E('p',{},this.connectionError),'error'); return; }
  }
  var r = await fs.exec('/etc/init.d/openflux', ['restart']);
  if (r.code) ui.addNotification(null, E('p', {}, (r.stderr || r.stdout || 'Не удалось применить настройки').slice(0,600)), 'error');
 },
 handleSave: async function() { await this.saveDomains(); await this.map.save(); await this.applyConfig(); },
 handleReset: function() { window.location.reload(); }
});
