// THROWAWAY UI prototype: three settings architectures on one route via ?variant=.
// No network, filesystem, Keychain, real clipboard, or durable storage operations.
const protocols = {
  chat: { name: 'OpenAI Chat Completions API', short: 'Chat Completions', endpoint: 'https://api.openai.com/v1/chat/completions', maxTemperature: 2 },
  responses: { name: 'OpenAI Responses API', short: 'Responses', endpoint: 'https://api.openai.com/v1/responses', maxTemperature: 2 },
  messages: { name: 'Anthropic Messages API', short: 'Messages', endpoint: 'https://api.anthropic.com/v1/messages', maxTemperature: 1 }
};
const variantNames = { A: '独立入口', B: '日报内分组', C: '概览与详情' };
const params = new URLSearchParams(location.search);
let variant = Object.hasOwn(variantNames, params.get('variant')) ? params.get('variant') : 'B';
let route = 'ai';
let serviceType = 'responses';
let state;
let editing;
let reportEditing;
let sourceEditing;
let zoneSearch = '';
let keyRevealed = false;
let changingKey = false;
let noticeTimer;
let operationSerial = 0;
let afterDialog;
const app = document.querySelector('#app');
const dialog = document.querySelector('#dialog');
const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const clone = value => structuredClone(value);
const button = (label, action, style = '', disabled = false) => `<button type="button" data-action="${action}" class="${style}" ${disabled ? 'disabled' : ''}>${label}</button>`;
const badge = (label, style = '') => `<span class="badge ${style}">${escapeHTML(label)}</span>`;
const option = (value, label, selected) => `<option value="${escapeHTML(value)}" ${value === selected ? 'selected' : ''}>${escapeHTML(label)}</option>`;

function emptyConfiguration() {
  return { endpoint: '', model: '', key: '', keyVersion: 0, temperature: '', effort: '', thinking: '', status: '未校验', streaming: '未知', structured: '未知', testedAt: '' };
}

function reset(scenario = 'first') {
  operationSerial++;
  const ready = { ...emptyConfiguration(), endpoint: 'https://relay.example/v1/responses', model: 'team-summary-model', key: 'DEMO-ONLY-FAKE-KEY-2468', keyVersion: 1, status: '已校验', streaming: '支持', structured: '支持', testedAt: '今天 09:20' };
  state = {
    services: { chat: emptyConfiguration(), responses: scenario === 'first' ? emptyConfiguration() : ready, messages: emptyConfiguration() },
    current: scenario === 'first' ? null : 'responses',
    report: { mode: 'follow', zone: 'Asia/Shanghai', language: 'zh', days: '1', preferences: '' },
    macZone: 'Asia/Shanghai',
    source: { executable: '/Users/demo/.local/bin/codex', directoryMode: 'auto', directory: '/Users/demo/.codex', status: '可用', checkedAt: '今天 09:18' },
    reports: [ { date:'2026-09-10', zone:'Asia/Shanghai' }, { date:'2026-09-09', zone:'Asia/Shanghai' }, { date:'2026-09-10', zone:'America/Los_Angeles' } ],
    drafts: [ { date:'2026-09-11', zone:'Asia/Shanghai' }, { date:'2026-09-08', zone:'Asia/Shanghai' }, { date:'2026-09-11', zone:'America/Los_Angeles' } ],
    snapshots: 5, selection: 6, keychainReadable: scenario !== 'locked', testRunning: false, testNote: '', credentialError:'', clipboard: '', deletedAll: false,
    effect: '初始示例状态。未调用任何真实服务。'
  };
  if (scenario === 'http') state.services.responses.endpoint = 'http://relay.example/v1/responses';
  if (scenario === 'stale') state.services.responses.status = '需要重新校验';
  if (scenario === 'source') { state.source.status = '不可用'; state.source.executable = '/Users/demo/missing/codex'; }
  serviceType = 'responses';
  editing = { ...clone(state.services.responses), pendingKey: '' };
  reportEditing = clone(state.report);
  sourceEditing = clone(state.source);
  changingKey = false;
  keyRevealed = false;
  zoneSearch = '';
  route = scenario === 'drafts' ? 'general' : scenario === 'source' ? 'source' : 'ai';
  document.querySelector('#key-failure').checked = false;
  render();
}

function configurationFields(config) {
  return { endpoint:config.endpoint.trim(), model:config.model.trim(), temperature:config.temperature === '' ? '' : Number(config.temperature), effort:config.effort, thinking:config.thinking };
}
function aiDirty() { return JSON.stringify(configurationFields(editing)) !== JSON.stringify(configurationFields(state.services[serviceType])) || Boolean(editing.pendingKey); }
function timezoneDirty() { return ['mode','zone'].some(key => reportEditing[key] !== state.report[key]); }
function preferencesDirty() { return ['language','days','preferences'].some(key => reportEditing[key] !== state.report[key]); }
function reportDirty() { return timezoneDirty() || preferencesDirty(); }
function sourceDirty() { return ['executable','directoryMode','directory'].some(key => sourceEditing[key] !== state.source[key]); }
function pageDirty() { return route === 'ai' ? aiDirty() : route === 'general' ? reportDirty() : route === 'source' ? sourceDirty() : false; }
function effectiveZone(report = state.report) { return report.mode === 'follow' ? state.macZone : report.zone; }
function validZone(zone) { try { new Intl.DateTimeFormat('en', { timeZone:zone }).format(); return true; } catch { return false; } }
function currentCanGenerate() { return state.current && state.services[state.current].status === '已校验' && Boolean(state.services[state.current].key) && state.keychainReadable && validZone(effectiveZone()); }
function offset(zone) { try { return new Intl.DateTimeFormat('en', { timeZone:zone, timeZoneName:'shortOffset' }).formatToParts(new Date('2026-09-11T04:00:00Z')).find(part => part.type === 'timeZoneName').value; } catch { return '无效时区'; } }

function field(id, label, value, placeholder = '', type = 'text', hint = '') {
  return `<div class="field"><label for="${id}">${label}</label><input id="${id}" name="${id}" type="${type}" value="${escapeHTML(value)}" placeholder="${escapeHTML(placeholder)}" autocomplete="off" spellcheck="false" aria-describedby="${id}-hint ${id}-error"><p id="${id}-hint" class="hint">${hint}</p><p id="${id}-error" class="error" hidden></p></div>`;
}
function heading(title, subtitle, extras = '') { return `<header class="detail-heading">${variant === 'C' && route !== 'overview' ? button('‹ 工作日报概览', 'overview', 'link-button back') : ''}<h2>${title}</h2><p>${subtitle}</p>${extras}</header>`; }
function navItem(key, title, subtitle, icon, active) { return `<button type="button" data-route="${key}" class="nav-item ${active ? 'active' : ''}" ${active ? 'aria-current="page"' : ''}><span class="icon" aria-hidden="true">${icon}</span><span>${title}<small>${subtitle}</small></span></button>`; }
function sideNavigation() {
  return `<nav class="sidebar" aria-label="设置分类">${navItem('monitor', '模型监控', '状态栏指标与刷新', '◉', route === 'monitor')}${navItem('bluetooth', '蓝牙解锁', '设备、距离与系统动作', '⌁', route === 'bluetooth')}<p class="sidebar-caption">工作复盘</p>${navItem(variant === 'C' ? 'overview' : 'general','工作日报',variant === 'A' ? '报告、来源与本地内容' : '报告、来源与 AI 服务','▤',!['ai','monitor','bluetooth'].includes(route) || variant !== 'A' && route === 'ai')}${variant === 'A' ? navItem('ai','AI 服务','连接、凭据与生成默认值','✧',route === 'ai') : ''}<p class="sidebar-note">${variantNames[variant]}<br>设置仅保存在这台 Mac</p></nav>`;
}
function sectionTabs() {
  const items = variant === 'A' ? [['general','常规'],['source','Codex 数据源'],['data','内容管理']] : [['general','常规'],['source','数据源'],['ai','AI 服务'],['data','内容管理']];
  return `<nav class="tabs" aria-label="工作日报设置分组">${items.map(([key,title]) => `<button type="button" data-route="${key}" class="${route === key ? 'active' : ''}" ${route === key ? 'aria-current="page"' : ''}>${title}</button>`).join('')}</nav>`;
}
function actionFooter(saveAction, dirty, label = '保存更改') {
  return `<footer class="actions"><p class="hint" id="dirty-label">${dirty ? '● 有未保存的更改' : '更改已保存'}${route === 'ai' ? ' · 保存不发起请求' : ''}</p><div class="inline">${button('撤销更改','revert','',!dirty)}${button(label,saveAction,'primary',!dirty)}</div></footer>`;
}

function renderAI() {
  const saved = state.services[serviceType];
  const isCurrent = state.current === serviceType;
  const statusStyle = saved.status === '已校验' ? 'good' : saved.status === '校验失败' ? 'bad' : 'warn';
  const top = `<div class="service-top"><div><label for="service-type">AI 服务类型</label><select id="service-type">${Object.entries(protocols).map(([key,p]) => option(key,p.name,serviceType)).join('')}</select></div>${isCurrent ? badge('当前配置') : button('设为当前','make-current','',saved.status !== '已校验' || aiDirty() || state.testRunning)}</div><p class="hint">类型表示请求协议。每种类型各保留一份配置，可连接官方服务或中转站。</p>`;
  const credential = `<div class="field"><div class="row"><label>API Key</label>${saved.key ? badge(state.keychainReadable ? '已存入本机 Keychain' : '暂时无法读取',state.keychainReadable ? '' : 'warn') : badge('尚未设置','warn')}</div>${saved.key ? `<output class="key-value mono" aria-label="已保存的 API Key">${keyRevealed ? escapeHTML(saved.key) : '••••••••••••••••••••'}</output><div class="row"><div class="inline">${button(keyRevealed ? '隐藏' : '显示','reveal-key','link-button',!state.keychainReadable)}${button('复制','copy-key','link-button',!state.keychainReadable)}</div><div class="inline">${button('更换…','replace-key','link-button',!state.keychainReadable)}${button('删除凭据…','delete-key','link-button danger',state.testRunning || aiDirty())}</div></div><p class="hint" id="delete-key-hint" ${aiDirty() ? '' : 'hidden'}>先保存或撤销配置编辑，再删除已存凭据。</p>` : ''}${!saved.key || changingKey ? field('new-key',saved.key ? '新的 API Key' : '填写 API Key',editing.pendingKey,'请输入此端点使用的 API Key','password',saved.key ? '留空保留已存值。新的凭据随「保存配置」提交。' : '通过服务方获取凭据，仅保存在本机 Keychain。') : ''}${state.credentialError ? `<p class="error" role="alert">${escapeHTML(state.credentialError)}</p>` : ''}<p class="hint">API Key 专用字段仅存本机 Keychain，不同步到其他 Mac。端点中手工写入的秘密不受这一承诺保护。</p></div>`;
  const advanced = `<details id="advanced"><summary>服务生成默认值 <span class="muted">· 可选</span></summary><div class="expanded">${field('temperature','温度',editing.temperature,`未设置；协议范围 0–${protocols[serviceType].maxTemperature}`,'text','留空时不发送，是否接受由具体模型和端点决定。')}${serviceType === 'messages' ? `<div class="field"><label for="thinking">思考模式</label><select id="thinking">${option('','跟随端点默认（不发送）',editing.thinking)}${option('disabled','关闭',editing.thinking)}${option('adaptive','自适应',editing.thinking)}</select></div>` : ''}<div class="field" id="effort-field" ${serviceType === 'messages' && editing.thinking !== 'adaptive' ? 'hidden' : ''}><label for="effort">${serviceType === 'messages' ? '自适应思考投入' : '思考强度'}</label><select id="effort">${['','none','minimal','low','medium','high','xhigh','max'].filter(v => serviceType !== 'messages' || !['none','minimal'].includes(v)).map(v => option(v,v || '未设置（不发送）',editing.effort)).join('')}</select><p class="hint">不同模型接受的选项不同；保存后测试配置确认。</p></div></div></details>`;
  const testDisabled = aiDirty() || state.testRunning || !state.keychainReadable;
  const stateSummary = `<section class="card service-status" aria-label="已保存配置的校验"><div class="row"><h3>已保存配置的校验</h3>${badge(saved.status,statusStyle)}</div><div class="capabilities"><span>基础文本 <b>${saved.status === '已校验' ? '通过' : '待通过'}</b></span><span>流式 <b>${saved.streaming}</b></span><span>结构化输出 <b>${saved.structured}</b></span></div>${saved.testedAt ? `<p class="hint">最近完成校验：${saved.testedAt}</p>` : ''}<div class="row">${button(state.testRunning ? '正在测试…' : '测试配置','test','',testDisabled)}${state.testRunning ? button('取消测试','cancel-test') : ''}<span class="hint" id="test-hint">${aiDirty() ? '先保存更改再测试。' : '最多 3 次合成文本请求，可能产生少量费用。'}</span></div><p class="hint">测试不会发送会话、日报正文或生成偏好，也不会设为当前配置。</p>${state.testNote ? `<p class="${saved.status === '校验失败' ? 'error' : 'hint'}" role="status">${escapeHTML(state.testNote)}</p>` : ''}</section>`;
  return `${heading(variant === 'B' ? '工作日报' : 'AI 服务',state.current ? `当前生成目标：${protocols[state.current].name}${currentCanGenerate() ? ' · 可生成' : ' · 暂不可生成'}` : '尚未选择当前配置；保存、测试后再明确选择。',variant === 'B' ? sectionTabs() : '')}<div class="scroll"><form id="ai-form" method="post" novalidate><section class="card">${top}</section>${!state.keychainReadable ? '<div class="status-block warn"><strong>暂时无法读取 Keychain</strong><p>已保存凭据仍然保留。测试与生成已暂停，恢复访问后再试。</p></div>' : ''}<section class="card">${field('endpoint','请求端点',editing.endpoint,protocols[serviceType].endpoint,'url','填写最终接收请求的完整 URL，不会自动追加路径。')}<p id="http-label" class="hint" ${editing.endpoint.trim().startsWith('http:') ? '' : 'hidden'}>${badge('明文 HTTP','warn')} 请求内容与凭据通过明文 HTTP 传输。</p><div class="separator"></div>${field('model','模型标识',editing.model,'填写此端点接受的精确模型名称','text','按服务方约定填写，不自动获取模型列表。')}<div class="separator"></div>${credential}<div class="separator"></div>${advanced}</section>${stateSummary}<details><summary>请求与本地数据边界</summary><div class="expanded hint">${serviceType === 'messages' ? 'Messages 不附加等价的通用服务端存储开关。' : '校验与生成均明确请求关闭生成对象存储；端点拒绝该控制时校验失败。'}不会自动跟随重定向。工作内容只在主动生成时外发；这不承诺服务方或中转站零保留。</div></details></form></div>${actionFooter('save-ai',aiDirty(),'保存配置')}`;
}

let timeZones;
try { timeZones = ['UTC',...Intl.supportedValuesOf('timeZone')]; } catch { timeZones = ['UTC','Asia/Shanghai','Asia/Tokyo','Europe/London','America/Los_Angeles','America/New_York']; }
function zoneOptions() {
  const common = ['Asia/Shanghai','Asia/Tokyo','America/Los_Angeles','Europe/London','UTC'];
  const query = zoneSearch.trim().toLowerCase();
  const aliases = { '上海':'Asia/Shanghai','东京':'Asia/Tokyo','伦敦':'Europe/London','洛杉矶':'America/Los_Angeles','纽约':'America/New_York' };
  const search = aliases[query] || query;
  let options = query ? timeZones.filter(zone => zone.toLowerCase().includes(search.toLowerCase())) : [...new Set([reportEditing.zone,...common,...timeZones])];
  return options.map(zone => option(zone,`${zone} · ${offset(zone)}`,reportEditing.zone)).join('');
}
function reportImpact() {
  const oldZone = effectiveZone();
  const newZone = effectiveZone(reportEditing);
  return { oldZone, newZone, affected:oldZone === newZone ? [] : state.drafts.filter(d => d.zone === oldZone) };
}
function reportImpactDescription() {
  const { oldZone,newZone,affected } = reportImpact();
  if (oldZone === newZone) return '<p>当前有效时区不会改变，已有草稿保留。</p>';
  return `<p>保存后从 <strong>${escapeHTML(oldZone)}</strong> 切换到 <strong>${escapeHTML(newZone)}</strong>，并重新扫描会话。</p><p>将不可恢复地删除旧时区所有日期的 <strong>${affected.length} 份草稿</strong>${affected.length ? `（${affected.map(d => d.date).join('、')}）` : ''}。已保存日报与目标时区的草稿保留。</p>`;
}
function renderGeneral() {
  const effective = effectiveZone();
  const timezone = `
    <p class="section-label">报告日边界</p>
    <section class="card">
      <h3>报告时区</h3>
      <label class="radio"><input type="radio" name="timezone-mode" value="follow" ${reportEditing.mode === 'follow' ? 'checked' : ''}>跟随 Mac</label>
      <label class="radio"><input type="radio" name="timezone-mode" value="fixed" ${reportEditing.mode === 'fixed' ? 'checked' : ''}>固定时区</label>
      <div id="fixed-zone" ${reportEditing.mode === 'fixed' ? '' : 'hidden'} class="expanded">
        <label for="zone-search">搜索时区</label>
        <input id="zone-search" type="search" value="${escapeHTML(zoneSearch)}" placeholder="城市或 IANA 名称，如上海、Asia/Shanghai">
        <label for="zone-picker" class="hint">选择固定时区 · ${escapeHTML(reportEditing.zone)}</label>
        <select id="zone-picker" size="4">${zoneOptions()}</select>
      </div>
      <div class="report-preview"><strong>当前有效：${escapeHTML(effective)} · ${offset(effective)}</strong><p>日报窗口只读显示此时区，按它划分报告日。</p></div>
      <div id="timezone-impact" class="hint" aria-live="polite">${reportImpactDescription()}</div>
      <p class="hint">跟随 Mac 自动变化时会直接切换并删除旧时区草稿，完成后告知数量。</p>
      <p class="error" id="timezone-error" role="alert" hidden></p>
    </section>
  `;
  const preferences = `
      <p class="section-label">生成设置</p>
    <section class="card">
      <div class="field"><label for="language">日报输出语言</label><select id="language">${option('zh','中文',reportEditing.language)}${option('en','English',reportEditing.language)}</select></div>
      <div class="field"><label for="preferences">生成偏好</label><textarea id="preferences" placeholder="例如：使用简洁要点，突出交付成果，保留项目术语。">${escapeHTML(reportEditing.preferences)}</textarea><p class="hint">用于调整语气、详略与侧重点；不改变所选输出语言、六个顶层章节或事实边界。只在主动生成时发送。</p></div>
      <div class="field"><label for="history-days">历史日报上下文</label><div class="inline"><input id="history-days" type="number" min="0" step="1" value="${escapeHTML(reportEditing.days)}"><span>个日历日</span></div><p class="hint">默认 1；0 表示不使用。仅采用同报告时区的已保存日报，缺失日期不向更早日期补位。</p><p class="error" id="report-error" hidden></p></div>
    </section>
  `;
  return `${heading('工作日报','设置报告日边界、输出语言和生成方式。',variant !== 'C' ? sectionTabs() : '')}<div class="scroll"><form id="report-form" method="post" novalidate>${timezone}${preferences}</form></div>${actionFooter('save-report',reportDirty())}`;
}
function renderSource() {
  return `${heading('Codex 数据源','从用户选择的本机 Codex 读取会话。',variant !== 'C' ? sectionTabs() : '')}<div class="scroll"><div class="status-block ${state.source.status === '不可用' ? 'warn' : ''}"><div class="row"><strong>当前状态</strong>${badge(state.source.status,state.source.status === '可用' ? 'good' : 'warn')}</div>${state.source.status === '不可用' ? '<p>选定的 Codex 可执行文件不存在，请重新选择。既有日报和草稿仍可查看、编辑。</p>' : '<p>已通过基础检查。扫描会话时仍会重新检查。</p>'}<p class="hint">上次成功检查：${state.source.checkedAt} · 版本仅用于诊断</p></div><form id="source-form" method="post" novalidate><section class="card">${field('executable','Codex 可执行文件',sourceEditing.executable,'选择本机 Codex 可执行文件','text','只使用这一入口，失效时不自动换用其他安装。')}<div class="inline">${button('选择文件…','choose-executable')}${button('重新发现','rediscover')}</div><div class="separator"></div><label for="directory-mode">Codex 数据目录</label><select id="directory-mode">${option('auto','自动解析',sourceEditing.directoryMode)}${option('custom','指定目录',sourceEditing.directoryMode)}</select><p class="hint">自动解析使用启动时的 CODEX_HOME，否则使用 ~/.codex。</p><div class="expanded">${field('directory',sourceEditing.directoryMode === 'auto' ? '当前解析目录' : '指定目录',sourceEditing.directory,'/Users/demo/.codex','text','示例路径，仅用于展示。')}</div>${button('选择目录…','choose-directory','',sourceEditing.directoryMode === 'auto')}<p class="hint">更改数据源会丢弃旧扫描的候选选择；已有会话快照、草稿和日报保留。</p></section></form>${button('重新检查当前数据源','check-source','',sourceDirty())}</div>${actionFooter('save-source',sourceDirty(),'保存并检查')}`;
}
function renderData() {
  return `${heading('日报内容管理','查看本机保留范围，清理所有报告日的内容。',variant !== 'C' ? sectionTabs() : '')}<div class="scroll"><section class="card"><h3>本机日报内容</h3><div class="history-counts"><div><b>${state.reports.length}</b><span>已保存日报</span></div><div><b>${state.drafts.length}</b><span>可恢复草稿</span></div><div><b>${state.snapshots}</b><span>关联会话快照</span></div></div><p class="hint">涵盖全部日期和报告时区。内容保留到你删除，不自动到期；应用不主动云同步。</p></section><section class="card"><h3>清空全部日报内容</h3><p>删除全部工作日报、日报草稿、会话快照及当前选择。</p><p class="hint">保留设置与 AI 服务凭据，不删除 Codex 原会话。相关生成会中止，迟到结果不能恢复已清空内容。</p><div class="separator"></div>${button('清空全部日报内容…','clear-data','danger',state.deletedAll)}<p class="hint">本地删除不能撤回已外发内容，也不清理系统备份或剪贴板。</p></section></div>`;
}
function renderOverview() {
  const entries = [ ['general','报告与生成设置',`${effectiveZone()} · ${state.report.language === 'zh' ? '中文' : 'English'} · 历史上下文 ${state.report.days} 天`,'◷'], ['source','Codex 数据源',`${state.source.status} · 一个本机数据源`,'⌘'], ['ai','AI 服务',state.current ? `${protocols[state.current].short} · ${state.services[state.current].status}` : '尚未配置当前生成目标','✧'], ['data','日报内容管理',`${state.reports.length} 份日报 · ${state.drafts.length} 份草稿`,'▤'] ];
  return `${heading('工作日报','按需进入各项设置。')}<div class="scroll"><div class="overview-hero">${badge(currentCanGenerate() ? '生成已就绪' : '完成设置后可生成',currentCanGenerate() ? 'good' : 'warn')}<h2>让每天的工作有迹可循</h2><p class="muted">查看来源和生成目标，设置报告日边界，<br>管理只保存在本机的工作内容。</p></div><div class="overview-list">${entries.map(([key,title,subtitle,icon]) => `<button type="button" class="overview-entry" data-route="${key}"><span class="icon" aria-hidden="true">${icon}</span><span><strong>${title}</strong><small>${escapeHTML(subtitle)}</small></span><span aria-hidden="true">›</span></button>`).join('')}</div></div>`;
}
function render() {
  const previousScroll = app.querySelector('.scroll')?.scrollTop || 0;
  const body = route === 'ai' ? renderAI() : route === 'general' ? renderGeneral() : route === 'source' ? renderSource() : route === 'data' ? renderData() : route === 'overview' ? renderOverview() : `<div class="empty"><h2>${route === 'monitor' ? '模型监控' : '蓝牙解锁'}</h2><p>现有设置占位，用于比较新入口的位置。</p>${button('返回工作日报','general')}</div>`;
  app.innerHTML = `${sideNavigation()}<main class="detail">${body}</main>`;
  if (route === 'ai' && state.testRunning) {
    app.querySelectorAll('#ai-form input,#ai-form select,[data-action=replace-key],[data-action=delete-key]').forEach(el => el.disabled = true);
  }
  if (route === 'source' && sourceEditing.directoryMode === 'auto') document.querySelector('#directory').readOnly = true;
  if (app.querySelector('.scroll')) app.querySelector('.scroll').scrollTop = previousScroll;
  document.querySelectorAll('[data-variant]').forEach(el => { el.classList.toggle('active', el.dataset.variant === variant); el.setAttribute('aria-pressed',String(el.dataset.variant === variant)); });
  document.querySelector('#window-meta').textContent = `${variant} · ${variantNames[variant]}`;
  renderState();
}
function renderState() {
  const saved = state.services[serviceType];
  const rows = [ ['正在编辑',protocols[serviceType].short], ['配置编辑',aiDirty() ? '有未保存更改' : '与已保存配置一致'], ['已存凭据',saved.key ? `存在 · 版本 ${saved.keyVersion}` : '没有'], ['新凭据',editing.pendingKey ? '已输入，待保存（不展示内容）' : '未输入；保留原值'], ['当前 AI 服务',state.current ? protocols[state.current].short : '未选择'], ['当前生成资格',currentCanGenerate() ? '可生成' : '不可生成'], ['已保存配置校验',`${saved.status} · 流式 ${saved.streaming} · 结构化 ${saved.structured}`], ['当前有效报告时区',effectiveZone()], ['未保存报告设置',reportDirty() ? '有更改' : '无'], ['各时区草稿',state.drafts.length ? [...new Set(state.drafts.map(d => d.zone))].map(zone => `${zone}：${state.drafts.filter(d => d.zone === zone).length} 份`).join('；') : '全部为空'], ['日报 / 快照 / 选择',`${state.reports.length} / ${state.snapshots} / ${state.selection}`], ['最近动作',state.effect], ['模拟剪贴板',state.clipboard ? '已复制虚构 Key（不写系统剪贴板）' : '空'] ];
  document.querySelector('#state').innerHTML = rows.map(([label,value]) => `<dt>${label}</dt><dd>${escapeHTML(value)}</dd>`).join('');
}
function showNotice(message) { const el = document.querySelector('#notice'); el.textContent = message; el.classList.add('visible'); clearTimeout(noticeTimer); noticeTimer = setTimeout(() => el.classList.remove('visible'),6500); }
function record(message) { state.effect = message; renderState(); }
function modal(title,description,actions) {
  if (dialog.open) dialog.close();
  dialog.innerHTML = `<h2 id="dialog-title">${title}</h2><div id="dialog-description">${description}</div><div class="dialog-actions">${actions.map((action,index) => `<button type="button" data-dialog-choice="${index}" class="${action.style || ''}" ${index === 0 ? 'autofocus' : ''}>${action.label}</button>`).join('')}</div>`;
  afterDialog = actions;
  dialog.showModal();
}
function leavePage(next) {
  if (state.testRunning && route === 'ai') {
    modal('取消测试并离开？','<p>这份配置正在测试。取消会终止本地请求并丢弃本次未完成的结果，原校验状态保持不变。</p><p class="hint">服务方或中转站可能仍继续计算。</p>',[
      {label:'继续测试'},
      {label:'取消测试并离开',action:() => { cancelTest(); keyRevealed = false; next(); }}
    ]);
    return;
  }
  if (!pageDirty()) { keyRevealed = false; next(); return; }
  const deleting = route === 'general' && reportImpact().affected.length;
  modal('保存更改后离开？',`<p>当前设置有未保存的更改。放弃后无法恢复本次输入。</p>${route === 'general' ? reportImpactDescription() : ''}`,[
    { label:'取消' },
    { label:'放弃更改', action:() => { revertPage(); keyRevealed = false; next(); } },
    { label:deleting ? `保存更改并删除 ${deleting} 份草稿` : '保存并继续', style:deleting ? 'danger-fill' : 'primary', action:() => savePage(() => { keyRevealed = false; next(); },true) }
  ]);
}
function navigate(next) { leavePage(() => { route = next; render(); app.querySelector('.scroll')?.scrollTo(0,0); }); }
function revertPage() {
  if (route === 'ai') { editing = { ...clone(state.services[serviceType]), pendingKey:'' }; changingKey = false; state.credentialError = ''; }
  if (route === 'general') reportEditing = clone(state.report);
  if (route === 'source') sourceEditing = clone(state.source);
  render();
}
function savePage(done,deletionConfirmed = false) {
  if (route === 'ai') saveAI(done);
  else if (route === 'general') saveReport(done,deletionConfirmed);
  else if (route === 'source') saveSource(done);
}
function fieldError(id,message) {
  const input = document.getElementById(id);
  const error = document.getElementById(`${id}-error`);
  if (input) { input.setAttribute('aria-invalid','true'); input.focus(); }
  if (error) { error.textContent = message; error.hidden = false; }
  showNotice(message);
}
function endpointError(value) {
  if (!value.trim()) return '';
  try { const url = new URL(value.trim()); if (!['http:','https:'].includes(url.protocol) || !url.hostname) return '请输入带主机名的完整 HTTP(S) URL。'; if (url.username || url.password) return '请求端点不能含用户名或密码，请使用 API Key 专用字段。'; if (url.hash || value.includes('#')) return '请求端点不能包含 #fragment，它不会发送给服务。'; } catch { return '请输入带主机名的完整 HTTP(S) URL。'; }
  return '';
}
function saveAI(done) {
  const error = endpointError(editing.endpoint);
  if (error) { fieldError('endpoint',error); return; }
  if (editing.temperature !== '' && (!Number.isFinite(Number(editing.temperature)) || Number(editing.temperature) < 0 || Number(editing.temperature) > protocols[serviceType].maxTemperature)) { document.querySelector('#advanced').open = true; fieldError('temperature',`温度应在 0–${protocols[serviceType].maxTemperature} 之间，或留空不发送。`); return; }
  if (editing.pendingKey && (!state.keychainReadable || document.querySelector('#key-failure').checked)) {
    state.credentialError = '保存失败：新凭据未写入 Keychain，旧凭据和已保存配置仍然保留。';
    record('模拟凭据替换失败。原配置未变，新输入仍可编辑。'); render(); document.querySelector('#new-key')?.focus(); return;
  }
  const saved = state.services[serviceType];
  if (aiDirty()) {
    Object.assign(saved,configurationFields(editing));
    if (editing.pendingKey) { saved.key = editing.pendingKey; saved.keyVersion++; }
    saved.status = saved.testedAt || saved.status !== '未校验' ? '需要重新校验' : '未校验';
    saved.streaming = '未知'; saved.structured = '未知';
    editing = { ...clone(saved), pendingKey:'' }; changingKey = false; keyRevealed = false; state.testNote = ''; state.credentialError = '';
  }
  record('配置已保存。没有网络请求，当前身份未改变。'); render(); showNotice('配置已保存；需要通过测试才能用于生成。'); done?.();
}
function testConfiguration() {
  const saved = state.services[serviceType];
  if (aiDirty() || state.testRunning || !state.keychainReadable) return;
  if (!saved.endpoint || !saved.model || !saved.key) {
    state.testNote = '配置不完整：请填写请求端点、模型标识和 API Key，并保存后再测试。'; render();
    if (!saved.endpoint) fieldError('endpoint','请填写请求端点并保存后再测试。');
    else if (!saved.model) fieldError('model','请填写模型标识并保存后再测试。');
    else fieldError('new-key','请填写 API Key 并保存后再测试。');
    return;
  }
  const serial = ++operationSerial;
  const type = serviceType;
  const result = document.querySelector('#test-result').value;
  state.testRunning = true;
  state.testNote = '正在发送合成文本，探测基础文本生成…';
  render();
  if (document.querySelector('#hold-test').checked) return;
  setTimeout(() => {
    if (serial !== operationSerial) return;
    state.testRunning = false;
    if (dialog.open && dialog.querySelector('#dialog-title').textContent === '取消测试并离开？') dialog.close();
    if (result === 'temporary') state.testNote = '本次校验因临时故障未完成，原校验状态保持不变。';
    else if (result === 'fail' || result === 'store' && type !== 'messages') { saved.status = '校验失败'; saved.streaming = '未知'; saved.structured = '未知'; saved.testedAt = '刚刚'; state.testNote = result === 'store' ? '端点拒绝关闭生成对象存储。请联系服务方或更换端点后重新测试。' : '服务明确拒绝此配置。请检查凭据、模型与协议后重新测试。'; }
    else { saved.status = '已校验'; saved.streaming = result === 'optional' ? '不支持' : '支持'; saved.structured = result === 'optional' ? '未知' : '支持'; saved.testedAt = '刚刚'; state.testNote = '基础文本已通过。测试仅更新校验结论，不改变当前选择。'; }
    editing = { ...clone(saved), pendingKey:'' };
    record(state.testNote); render();
  },3500);
}
function cancelTest() { operationSerial++; state.testRunning = false; state.testNote = '测试已在本机取消；原校验状态保持不变。'; record(state.testNote); render(); }
function saveReport(done,deletionConfirmed = false) {
  if (!validZone(effectiveZone(reportEditing))) {
    const error = document.querySelector('#timezone-error'); error.hidden = false; error.textContent = '固定时区无效，请重新选择；不会自动回退。'; document.querySelector('#zone-picker').focus(); return;
  }
  if (reportEditing.days === '' || !Number.isInteger(Number(reportEditing.days)) || Number(reportEditing.days) < 0) {
    const error = document.querySelector('#report-error'); error.hidden = false; error.textContent = '请输入 0 或更大的整数。'; document.querySelector('#history-days').setAttribute('aria-invalid','true'); document.querySelector('#history-days').focus(); return;
  }
  const { oldZone,newZone,affected } = reportImpact();
  const apply = () => {
    if (oldZone !== newZone) { state.drafts = state.drafts.filter(d => d.zone !== oldZone); state.selection = 6; state.snapshots = Math.max(0,state.snapshots - affected.length); }
    state.report = clone(reportEditing);
    record(oldZone === newZone ? '常规设置已一起保存，有效时区未改变，草稿保留。' : `常规设置已一起保存，切换到 ${newZone}；删除旧时区 ${affected.length} 份草稿，保留目标时区草稿与全部已保存日报，并重新扫描。`);
    render(); showNotice(state.effect); done?.();
  };
  if (affected.length && !deletionConfirmed) modal('保存更改并删除旧时区草稿？',reportImpactDescription() + '<p>输出语言、生成偏好与历史回看天数的更改将一并保存。</p>',[
    {label:'取消'},
    {label:`保存更改并删除 ${affected.length} 份草稿`,style:'danger-fill',action:apply}
  ]);
  else apply();
}
function saveSource(done) {
  if (!sourceEditing.executable.trim()) { fieldError('executable','请选择 Codex 可执行文件。'); return; }
  if (!sourceEditing.directory.trim()) { fieldError('directory','请选择有效数据目录。'); return; }
  state.source = clone(sourceEditing); state.source.status = '未检查'; state.selection = 0;
  record('数据源已切换，旧扫描候选与选择已清除。已有会话快照、草稿和日报保留。'); render();
  checkSource(); done?.();
}
function checkSource() { state.source.status = state.source.executable.includes('missing') ? '不可用' : '可用'; if (state.source.status === '可用') state.source.checkedAt = '刚刚'; sourceEditing = clone(state.source); render(); showNotice(state.source.status === '可用' ? '当前数据源通过基础检查。' : '选定的 Codex 文件不存在，请重新选择。'); }
function deleteKey() {
  if (aiDirty()) { showNotice('先保存或撤销配置编辑，再删除已保存凭据。'); return; }
  const saved = state.services[serviceType];
  modal('删除这份配置的 API Key？',`<p>删除 <strong>${protocols[serviceType].name}</strong> 保存在本机 Keychain 的凭据。</p><p>请求端点、模型与默认值保留。${state.current === serviceType ? '这份配置仍保持当前身份，但不能生成日报。' : '这份配置在重新填写和校验前不能设为当前。'}</p>`,[{label:'取消'},{label:'删除凭据',style:'danger-fill',action:() => {
    if (document.querySelector('#key-failure').checked || !state.keychainReadable) { state.credentialError = '删除失败：凭据尚未删除，已保存内容保持不变。'; record('模拟 Keychain 删除失败。没有声称删除成功。'); render(); return; }
    saved.key = ''; saved.keyVersion++; saved.status = '需要重新校验'; saved.streaming = '未知'; saved.structured = '未知'; editing = {...clone(saved),pendingKey:''}; keyRevealed = false; state.credentialError = '';
    record('仅删除此类型的已存凭据。其他配置不变，当前身份不变。'); render(); showNotice('凭据已删除。重新填写后需要测试配置。');
  }}]);
}
function clearData() {
  modal('清空全部日报内容？',`<p>这会不可恢复地删除所有日期和报告时区的：</p><ul><li>${state.reports.length} 份已保存工作日报</li><li>${state.drafts.length} 份日报草稿</li><li>${state.snapshots} 份会话快照及当前会话选择</li></ul><p><strong>设置、AI 服务凭据与 Codex 原会话保留。</strong></p><p class="hint">相关生成会中止。不能撤回已外发内容，也不清理系统备份、系统剪贴板或服务方副本。</p>`,[{label:'取消'},{label:'清空全部日报内容',style:'danger-fill',action:() => { state.reports = []; state.drafts = []; state.snapshots = 0; state.selection = 0; state.deletedAll = true; record('全部日报内容已清空，设置与三种服务凭据保留。'); render(); showNotice(state.effect); }}]);
}
function macChange() {
  const oldZone = effectiveZone();
  state.macZone = state.macZone === 'Asia/Shanghai' ? 'America/Los_Angeles' : 'Asia/Shanghai';
  if (state.report.mode !== 'follow') { record(`Mac 时区变为 ${state.macZone}。使用固定报告时区，日报内容不变。`); render(); showNotice(state.effect); return; }
  const count = state.drafts.filter(d => d.zone === oldZone).length;
  state.drafts = state.drafts.filter(d => d.zone !== oldZone); state.snapshots = Math.max(0,state.snapshots - count); state.selection = 6;
  record(`已跟随 Mac 切换到 ${state.macZone}，删除旧时区 ${count} 份草稿并重新扫描；已保存日报保留。`); render(); showNotice(state.effect);
}
function switchVariant(next) {
  leavePage(() => { variant = next; if (next === 'C') route = 'overview'; else if (route === 'overview') route = 'general'; const url = new URL(location.href); url.searchParams.set('variant',next); history.replaceState(null,'',url); render(); });
}
function changedControls() {
  const label = document.querySelector('#dirty-label');
  if (label) label.textContent = `${pageDirty() ? '● 有未保存的更改' : '更改已保存'}${route === 'ai' ? ' · 保存不发起请求' : ''}`;
  document.querySelectorAll('[data-action=revert],[data-action=save-ai],[data-action=save-report],[data-action=save-source]').forEach(el => el.disabled = !pageDirty());
  if (route === 'general') document.querySelector('#timezone-impact').innerHTML = reportImpactDescription();
  if (route === 'ai') {
    const deleteButton = document.querySelector('[data-action=delete-key]'); if (deleteButton) deleteButton.disabled = aiDirty() || state.testRunning;
    const deleteHint = document.querySelector('#delete-key-hint'); if (deleteHint) deleteHint.hidden = !aiDirty();
    const test = document.querySelector('[data-action=test]'); if (test) test.disabled = aiDirty() || state.testRunning || !state.keychainReadable;
    const current = document.querySelector('[data-action=make-current]'); if (current) current.disabled = aiDirty() || state.services[serviceType].status !== '已校验' || state.testRunning;
    const hint = document.querySelector('#test-hint'); if (hint) hint.textContent = aiDirty() ? '先保存更改再测试。' : '最多 3 次合成文本请求，可能产生少量费用。';
    const http = document.querySelector('#http-label'); if (http) http.hidden = !editing.endpoint.trim().startsWith('http:');
  }
  renderState();
}
document.addEventListener('input',event => {
  const el = event.target;
  const fields = { endpoint:'endpoint',model:'model','new-key':'pendingKey',temperature:'temperature' };
  if (fields[el.id]) { editing[fields[el.id]] = el.value; el.removeAttribute('aria-invalid'); const error = document.getElementById(`${el.id}-error`); if (error) error.hidden = true; }
  if (el.id === 'preferences') reportEditing.preferences = el.value;
  if (el.id === 'history-days') { reportEditing.days = el.value; el.removeAttribute('aria-invalid'); document.querySelector('#report-error').hidden = true; }
  if (el.id === 'executable') sourceEditing.executable = el.value;
  if (el.id === 'directory') sourceEditing.directory = el.value;
  if (el.id === 'zone-search') { zoneSearch = el.value; document.querySelector('#zone-picker').innerHTML = zoneOptions(); }
  changedControls();
});
document.addEventListener('change',event => {
  const el = event.target;
  if (el.id === 'scenario') { const url = new URL(location.href); url.searchParams.set('scenario',el.value); history.replaceState(null,'',url); reset(el.value); }
  if (el.id === 'service-type') { const next = el.value; el.value = serviceType; leavePage(() => { serviceType = next; editing = {...clone(state.services[next]),pendingKey:''}; changingKey = false; state.testNote = ''; state.credentialError = ''; render(); app.querySelector('.scroll')?.scrollTo(0,0); }); }
  if (el.id === 'effort') editing.effort = el.value;
  if (el.id === 'thinking') { editing.thinking = el.value; if (el.value !== 'adaptive') editing.effort = ''; document.querySelector('#effort-field').hidden = el.value !== 'adaptive'; }
  if (el.name === 'timezone-mode') { reportEditing.mode = el.value; document.querySelector('#fixed-zone').hidden = el.value !== 'fixed'; }
  if (el.id === 'zone-picker') reportEditing.zone = el.value;
  if (el.id === 'language') reportEditing.language = el.value;
  if (el.id === 'directory-mode') { sourceEditing.directoryMode = el.value; if (el.value === 'auto') sourceEditing.directory = '/Users/demo/.codex'; render(); }
  changedControls();
});
document.addEventListener('submit',event => {
  event.preventDefault();
  savePage();
});
document.addEventListener('click',event => {
  const choice = event.target.closest('[data-dialog-choice]');
  if (choice) { const selected = afterDialog[Number(choice.dataset.dialogChoice)]; dialog.close(); selected.action?.(); return; }
  const target = event.target.closest('button'); if (!target || target.disabled) return;
  if (target.dataset.route) { navigate(target.dataset.route); return; }
  if (target.dataset.variant) { switchVariant(target.dataset.variant); return; }
  const action = target.dataset.action;
  if (target.id === 'close-window') { leavePage(() => { app.innerHTML = `<div class="empty"><h2>设置窗口已关闭</h2><p>原型模拟结束。日报草稿与保存的配置仍然保留。</p>${button('重新打开设置','reopen','primary')}</div>`; }); return; }
  const actions = {
    'general':() => navigate('general'), 'overview':() => navigate('overview'), 'reopen':render,
    'save-ai':() => saveAI(), 'save-report':() => saveReport(), 'save-source':() => saveSource(), 'revert':revertPage,
    'test':testConfiguration,
    'cancel-test':cancelTest,
    'make-current':() => { if (state.services[serviceType].status !== '已校验' || aiDirty()) return; state.current = serviceType; record(`已明确选择 ${protocols[serviceType].short} 为当前配置，没有发送工作内容。`); render(); showNotice('已设为当前配置。'); },
    'replace-key':() => { changingKey = true; render(); document.querySelector('#new-key').focus(); },
    'reveal-key':() => { if (!state.keychainReadable) return; keyRevealed = !keyRevealed; render(); },
    'copy-key':() => { if (!state.keychainReadable) return; state.clipboard = state.services[serviceType].key; record('主动复制已存凭据；仅模拟，不写系统剪贴板。'); showNotice('已复制 API Key。'); },
    'delete-key':deleteKey, 'clear-data':clearData, 'check-source':checkSource,
    'rediscover':() => { sourceEditing.executable = '/Users/demo/.local/bin/codex'; render(); record('已模拟发现 Codex 入口，保存后才切换数据源。'); },
    'choose-executable':() => { sourceEditing.executable = '/opt/homebrew/bin/codex'; render(); record('模拟文件选择器已选中 /opt/homebrew/bin/codex。'); },
    'choose-directory':() => { sourceEditing.directory = '/Users/demo/CodexWork'; render(); record('模拟目录选择器已选中 /Users/demo/CodexWork。'); },
    'mac-change':macChange,
    'toggle-keychain':() => { state.keychainReadable = !state.keychainReadable; keyRevealed = false; if (!state.keychainReadable && state.testRunning) { operationSerial++; state.testRunning = false; } record(state.keychainReadable ? 'Keychain 可读状态已恢复，尚未发起任何请求。' : 'Keychain 暂时不可读，已存凭据保留，测试与生成暂停。'); render(); },
    'late-result':() => { record(state.deletedAll ? '清空前生成的迟到结果已丢弃。日报、草稿、快照与选择仍然为空。' : '尚未清空全部内容。请先进入内容管理完成清空场景。'); showNotice(state.effect); },
    'previous-variant':() => switchVariant(['C','A','B'][['A','B','C'].indexOf(variant)]),
    'next-variant':() => switchVariant(['B','C','A'][['A','B','C'].indexOf(variant)])
  };
  actions[action]?.();
});
document.addEventListener('keydown',event => {
  if (event.isComposing || dialog.open || event.target.closest('input,textarea,select,[contenteditable],summary')) return;
  if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') { event.preventDefault(); const variants = ['A','B','C']; switchVariant(variants[(variants.indexOf(variant) + (event.key === 'ArrowRight' ? 1 : 2)) % 3]); }
});
const initialScenario = [...document.querySelector('#scenario').options].some(o => o.value === params.get('scenario')) ? params.get('scenario') : 'first';
document.querySelector('#scenario').value = initialScenario;
document.querySelector('#pending-decisions').textContent = '已选择 B 日报内分组。常规设置一起保存；时区字段预告草稿影响。保存与草稿删除采用一次统一确认；清空一次确认。允许保存不完整配置；测试中离开先确认取消；删除凭据先处理编辑。原型与共享理解已确认（2026-09-14）。';
reset(initialScenario);
if (variant === 'C') { route = 'overview'; render(); }
