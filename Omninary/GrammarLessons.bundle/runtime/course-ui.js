(()=>{
  'use strict';
  const root=document.getElementById('gram-iphone-v4');
  const data=window.gramCourseData;
  if(!data?.parts?.length||!data.releaseID)throw new Error('Chưa nhận được phiên bản học liệu hợp lệ.');
  const partCount=data.parts.length,partPages=Math.ceil(partCount/9),topicNumber=String(data.topicNumber||1).padStart(2,'0'),topicLabel='Chủ điểm '+topicNumber;
  const q=s=>root.querySelector(s),app=q('#g-app'),audio=q('#g-voice'),canvas=q('#g-actor');
  const core=GramCourse,rules={...GramLessonRules,...data.teachingRules},lecture=GramLecture,ids=data.parts.map(p=>p.id);
  const defaultTheoryTab=['meaning','structure','context'].includes(data.defaultTheoryTab)?data.defaultTheoryTab:'meaning';
  const names={easy:'Dễ',medium:'Vừa',hard:'Khó'};
  const writer='gram-v5-'+Date.now()+'-'+Math.random().toString(36).slice(2);
  const state={progress:core.fresh(),view:'topic',part:0,listPage:0,example:0,role:'',tab:defaultTheoryTab,compare:false,revealed:false,pronoun:'I',verb:null,pair:0,contracted:false,level:'easy',question:0,answers:[],choice:null,typed:'',submitted:false,rate:1,activeAttempt:'',attemptStarted:0,deadline:0,heard:{},lectureDone:false,lectureStarted:false,pairSpeaking:false,practiceBoard:false,demoPair:null,history:[],selectedAttempt:'',resultBack:'topic'};
  let historyLoaded=false,historyLoading=false,historyError='',historyMore=false,historyOffset=0;
  let completionSaving=false,completionError='',pendingCompletion=null;
  const audioBlobs=new Map();
  let voiceLoading=false;
  let actor,voicePart=-1,voiceTrack='',lastCueKey='',token=0,clock=0,lastUI=0,toast='',voiceError='',soundContext,toastTimeout;
  const e=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const icon=name=>'<i data-lucide="'+name+'" aria-hidden="true"></i>';
  const fmt=n=>{n=Math.max(0,Math.floor(n||0));return Math.floor(n/60)+':'+String(n%60).padStart(2,'0')};
  const timerFmt=n=>String(Math.floor(n/60)).padStart(2,'0')+':'+String(n%60).padStart(2,'0');
  const dateLabel=stamp=>new Intl.DateTimeFormat('vi-VN',{day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit',timeZone:'Asia/Ho_Chi_Minh'}).format(new Date(stamp));
  const card=()=>data.parts[state.part];
  const question=()=>data.exercises[state.level][state.question];
  const questionCount=()=>data.exercises[state.level].length;
  const exerciseCounts=Object.fromEntries(Object.entries(data.exercises).map(([level,bank])=>[level,bank.length]));
  const readCount=()=>ids.filter(id=>state.progress.read[id]).length;
  const complete=()=>core.theoryDone(state.progress,ids);
  const stars=()=>core.stars(state.progress);
  const pronoun=()=>rules.pronouns.find(p=>p.word===state.pronoun);
  const objectMatch=()=>card().kind==='object-pair';
  const pairAnswer=()=>objectMatch()?pronoun().object:pronoun().verb;
  const canMatch=()=>objectMatch()||card().kind==='affirmative'||rules.matchingPartIDs.includes(card().id)||card().kind==='pronoun';
  const actorMount=()=>'<div class="g-actor-mount"></div>';
  const starText=n=>'★'.repeat(n)+'☆'.repeat(3-n);
  function clearAttempt(){state.answers=Array(questionCount()).fill(null);state.question=0;state.choice=null;state.typed='';state.submitted=false;state.activeAttempt='';state.deadline=0;state.attemptStarted=0;pendingCompletion=null;completionError=''}
  function restore(saved){
    const s=saved?.privateContent?.gramV4;if(s?.version!==4)return false;
    state.progress=core.restore(s.progress,ids,exerciseCounts);state.heard=(!s.lessonVersion||s.lessonVersion===data.releaseID)&&s.heard&&typeof s.heard==='object'?s.heard:{};
    state.part=Math.max(0,Math.min(partCount-1,Number(s.part)||0));state.listPage=Math.floor(state.part/9);
    state.level=core.levels.includes(s.level)?s.level:'easy';if([1,.85,1.25,1.5].includes(s.rate))state.rate=s.rate;
    state.view='topic';clearAttempt();return true;
  }
  restore(window.gramNative.state);
  function resetInteraction(){
    state.example=0;state.role='';state.tab=defaultTheoryTab;state.compare=false;state.revealed=false;state.pair=card().wordChangeIDs?.[0]??0;state.contracted=false;state.verb=null;state.wordChangePractice=false;
    state.pronoun=rules.initialPronouns[card().id]||'I';
    state.lectureDone=state.heard[card().id]===true;state.lectureStarted=false;state.pairSpeaking=false;state.practiceBoard=false;state.demoPair=null;lastCueKey='';
    if(state.lectureDone)adoptLecturePair();
  }
  function adoptLecturePair(){const scene=lecture.sceneAt(card(),Infinity);if(canMatch()&&rules.pronouns.some(p=>p.word===scene.subject)){state.pronoun=scene.subject;state.verb=scene.verb||null}if(scene.kind==='word-change'&&card().wordChangeIDs?.includes(scene.pair)){state.pair=scene.pair;state.contracted=Boolean(scene.changed)}}
  resetInteraction();
  actor=new ProfessorGram.Animator({canvas,atlas:data.atlas,audio,chapters:[...data.parts,...data.contractionDemos].map(p=>p.audioInfo),reducedMotion:matchMedia('(prefers-reduced-motion: reduce)').matches});
  // Only achievements and lesson preferences leave this screen. An unfinished quiz never does.
  function snapshot(progress=state.progress){return {modelContent:{screen:state.view,currentPart:state.part+1,theoryPartsRead:readCount(),stars:core.stars(progress)},privateContent:{writer,gramV4:{version:4,lessonVersion:data.releaseID,progress,heard:state.heard,view:'topic',part:state.part,level:state.level,rate:state.rate}}}}
  function persist(){window.gramNative.saveState(snapshot()).catch(()=>{})}
  function applyAppearance(){window.gramNative.applyTheme()}
  function announce(text){q('#g-announcement').textContent=text}
  function stop(){token++;voiceLoading=false;audio.pause();cancelAnimationFrame(clock)}
  function toolbar(title,subtitle='',back='topic',end='',endAction='parts',sky=false){
    return '<header class="'+(sky?'g-sky-header':'')+'"><div class="g-toolbar"><button type="button" class="g-icon-btn" data-action="'+back+'" aria-label="Quay lại">'+icon('arrow-left')+'</button><div><strong>'+e(title)+'</strong>'+(subtitle?'<small>'+e(subtitle)+'</small>':'')+'</div>'+(end?'<button type="button" class="g-toolbar-end" data-action="'+endAction+'">'+end+'</button>':'')+'</div></header>';
  }
  function navigate(view){if(completionSaving){showToast('Đang lưu kết quả…');return}stop();if(state.view==='exercise'&&view!=='exercise')clearAttempt();state.view=view;toast='';render();persist();if(view==='history'&&!historyLoaded)loadHistory(true)}
  function showToast(text){toast=text;q('.g-toast')?.remove();app.insertAdjacentHTML('beforeend','<p class="g-toast" role="status">'+e(text)+'</p>');clearTimeout(toastTimeout);toastTimeout=setTimeout(()=>{q('.g-toast')?.remove();toast=''},2600)}
  function render(){
    const views={topic:topicView,theory:theoryView,parts:partsView,exercise:exerciseView,result:resultView,history:historyView};
    root.dataset.screen=state.view;root.dataset.sky='false';
    if(document.activeElement?.id==='g-typed')document.activeElement.blur();
    app.innerHTML=(views[state.view]||topicView)();
    const mount=q('.g-actor-mount');canvas.hidden=!mount;if(mount)mount.appendChild(canvas);
    if(globalThis.lucide)lucide.createIcons({attrs:{width:16,height:16}});
    if(state.view==='theory'){lastCueKey=JSON.stringify(currentScene());updateAudioUI()}
    window.gramNative.screenChanged(state.view);updateTimer();focusAnswer();
  }
  const answerFocusKey=()=>state.activeAttempt+':'+state.level+':'+state.question;
  function focusAnswer(){
    if(state.view!=='exercise'||state.submitted||question().type==='choice')return;
    const input=q('#g-typed');if(!input)return;
    input.dataset.focusKey=answerFocusKey();
    if(window.gramNative.focusAnswer)window.gramNative.focusAnswer(input.dataset.focusKey);
    else window.gramFocusAnswer({key:input.dataset.focusKey});
  }
  // Native evaluation opens the iPhone keyboard. Ignore replies for a question already left.
  window.gramFocusAnswer=({key}={})=>{
    if(state.view!=='exercise'||state.submitted||question().type==='choice'||key!==answerFocusKey())return false;
    const input=q('#g-typed');if(!input||input.readOnly||input.dataset.focusKey!==key)return false;
    input.focus({preventScroll:true});return true;
  };
  function topicView(){
    const n=stars(),read=readCount();
    return toolbar(topicLabel,e(data.stage+' · '+data.stageTitle),'exit','','parts',false)+'<div class="g-topic-content"><section class="g-hero"><div class="g-hero-copy"><p class="g-kicker">CHỦ ĐIỂM '+topicNumber+' / '+data.topicCount+'</p><h1>'+e(data.title).replace(' &amp; ',' &amp;<br>')+'</h1><p>'+e(data.titleVi)+'</p></div>'+actorMount()+'</section><div class="g-stars-row"><span class="g-stars" aria-label="'+n+' trên 3 sao">'+starText(n)+'</span><p>'+(n>=2?'Đã đủ điều kiện qua chủ điểm kế tiếp.':'Đạt 2 sao để qua chủ điểm kế tiếp.')+'</p></div><section class="g-theory-card"><div class="g-row"><span class="g-theory-symbol">'+icon('book-open')+'</span><div><h3>Học lý thuyết</h3><small class="g-muted">Luôn mở để xem lại</small></div><span>'+read+'/'+partCount+' phần</span></div><div class="g-track" aria-label="Đã học '+read+' trên '+partCount+' phần"><span style="width:'+read/partCount*100+'%"></span></div><div class="g-topic-actions"><button type="button" class="g-btn g-primary" data-action="learn">'+icon(complete()?'rotate-ccw':'play')+(complete()?'Xem lại lý thuyết':read?'Học tiếp':'Vào học lý thuyết')+'</button><button type="button" class="g-btn" data-action="parts" aria-label="Danh sách '+partCount+' phần">'+icon('list')+partCount+' phần</button></div></section><section class="g-topic-practice"><div class="g-section-row"><h3>Làm bài tập</h3><span>Dễ · Vừa · Khó</span></div><div class="g-levels">'+core.levels.map((level,i)=>{const open=core.unlocked(state.progress,ids,level),done=state.progress.done[level];return '<button type="button" class="g-level" data-level="'+level+'" '+(!open?'disabled':'')+'><span class="g-level-badge">'+(i+1)+'</span><span class="g-level-copy"><strong>'+names[level]+' <span class="g-gold">'+starText(i+1)+'</span></strong><small>'+(done?'Tốt nhất '+state.progress.best[level]+'/'+data.exercises[level].length+' · làm lại':open?requirement(level):i===0?'Học xong lý thuyết để mở':'Đạt mức '+names[core.levels[i-1]]+' để mở')+'</small></span>'+icon(done?'rotate-ccw':open?'chevron-right':'lock-keyhole')+'</button>'}).join('')+'</div><button type="button" class="g-history-link" data-action="history">'+icon('history')+'<span><strong>Lịch sử làm bài</strong><small>Xem các lần đã hoàn thành</small></span>'+icon('chevron-right')+'</button></section></div>';
  }
  function partsView(){
    const start=state.listPage*9;
    return toolbar('Danh sách '+partCount+' phần','Lý thuyết · mỗi phần một ý')+'<div class="g-parts"><h2>Chọn phần muốn học</h2><div class="g-parts-list">'+data.parts.slice(start,start+9).map((p,i)=>'<button type="button" data-part="'+(start+i)+'" class="g-part-item '+(state.progress.read[p.id]?'read':'')+'"><span class="g-part-number">'+String(start+i+1).padStart(2,'0')+'</span><span><strong>'+e(p.title)+'</strong><small>'+e(p.group)+'</small></span>'+icon(state.progress.read[p.id]?'circle-check':'chevron-right')+'</button>').join('')+'</div><div class="g-list-pager"><button type="button" class="g-icon-btn" data-action="list-previous" '+(state.listPage===0?'disabled':'')+' aria-label="Trang trước">'+icon('chevron-left')+'</button><span>Phần '+(start+1)+'–'+Math.min(start+9,partCount)+' / '+partCount+'</span><button type="button" class="g-icon-btn" data-action="list-next" '+(state.listPage===partPages-1?'disabled':'')+' aria-label="Trang sau">'+icon('chevron-right')+'</button></div></div>';
  }
    const roleHelp=rules.roleHelp;
  const unlocked=()=>state.lectureDone&&!state.lectureStarted&&!state.pairSpeaking;
  const partKey=()=> 'part:'+state.part;
  const demoKey=i=>'demo:'+i;
  function activeTrack(){return state.demoPair!==null?data.contractionDemos[state.demoPair]:card()}
  function displayExample(){
    const c=card();let x=c.examples[Math.min(state.example,c.examples.length-1)];if(!x)return null;x={...x};
    if(c.kind==='negative'&&state.compare)x=rules.examples.positive;
    if(c.kind==='question'&&state.compare)x=rules.examples.statement;
    return x;
  }
  function currentScene(){
    if(state.practiceBoard&&unlocked()){
      if(canMatch())return {kind:'pair',subject:pronoun().word,verb:state.verb||'?',manual:true};
      if(card().kind==='contraction')return {kind:'contraction',pair:state.pair,contracted:state.contracted};
      if(card().wordChangeIDs?.length&&(card().kind==='word-change'||state.wordChangePractice))return {kind:'word-change',pair:state.pair,changed:state.contracted};
      if(card().kind==='repair')return {kind:'repair',fixed:state.revealed,meaning:true};
      if(card().kind==='checklist')return {kind:'checklist',active:3};
      return {kind:'example',example:state.example,meaning:true,manual:true};
    }
    if(state.demoPair!==null&&voiceTrack===demoKey(state.demoPair))return lecture.sceneAt(activeTrack(),audio.currentTime);
    if(voiceTrack===partKey())return lecture.sceneAt(card(),audio.currentTime);
    return lecture.sceneAt(card(),state.lectureDone?Infinity:0);
  }
  function sceneExample(scene){
    let x=scene.manual?displayExample():card().examples[scene.example||0];if(!x)return null;x={...x};
    if(scene.variant==='question')x=rules.examples.busyQuestion;
    if(scene.variant==='answer')x=rules.examples.busyAnswer;
    if(scene.variant==='contracted')x=rules.examples.contracted;
    return x;
  }
  function sentence(x,focus=''){
    return lecture.tokens(x).map(piece=>piece.role?'<button type="button" class="g-word '+(piece.role===focus?'g-focus':'')+(unlocked()&&piece.role===state.role?' g-selected':'')+'" data-role="'+piece.role+'" '+(!unlocked()?'disabled':'')+'>'+e(piece.text)+'</button>':e(piece.text)).join('');
  }
  function boardView(scene){
    const c=card();let out='';
    if(scene.kind==='example'){
      const x=sceneExample(scene);
      out='<p class="g-board-label">'+e(c.examples.length>1?'VÍ DỤ '+((scene.example||0)+1):c.title)+'</p><div class="g-sentence">'+(x?sentence(x,scene.focus):'')+'</div>'+(scene.meaning&&x?'<p class="g-translation '+(scene.focus==='meaning'?'g-current-meaning':'')+'">'+e(x.vi)+'</p>':'')+(scene.note?'<p class="g-scene-note">'+e(scene.note)+'</p>':'');
    }else if(scene.kind==='pair'){
      const result=scene.manual?(!state.verb?'unselected':state.verb===pairAnswer()?'correct':'wrong'):'correct';
      out='<p class="g-board-label">'+(objectMatch()?'CHỦ NGỮ ↔ TÂN NGỮ':'CHỦ NGỮ ↔ ĐỘNG TỪ')+'</p><div class="g-pair-board"><span>'+e(scene.subject)+'</span>'+icon('link')+'<strong data-state="'+result+'" class="'+(result==='wrong'?'wrong':'')+'">'+e(scene.verb)+'</strong></div>';
    }else if(scene.kind==='subject')out='<p class="g-board-label">ĐẠI TỪ CHỦ NGỮ</p><p class="g-formula">'+e(scene.subject)+'</p><p class="g-translation">'+e(scene.person)+'</p>';
    else if(scene.kind==='formula')out='<p class="g-board-label">CẤU TRÚC CHÍNH</p><p class="g-formula g-formula-pieces"><span class="'+(scene.focus==='subject'?'g-focus':'')+'">Chủ ngữ</span> + <strong class="'+(scene.focus==='verb'?'g-focus':'')+'">'+e(rules.formulaVerbText)+'</strong> + <span class="'+(scene.focus==='complement'?'g-focus':'')+'">bổ ngữ</span></p>';
    else if(scene.kind==='overview')out='<p class="g-board-label">TO BE · ĐỘNG TỪ NỐI</p><p class="g-formula">Chủ ngữ ↔ bổ ngữ</p><p class="g-translation">Danh từ · tính từ · nơi chốn</p>';
    else if(scene.kind==='info')out='<p class="g-board-label">'+e(scene.title)+'</p><p class="g-scene-info">'+e(scene.text)+'</p>';
    else if(scene.kind==='negative'){
      const x=scene.negative?rules.examples.negative:rules.examples.positive;
      out='<p class="g-board-label">'+(scene.negative?'THÊM NOT SAU ĐỘNG TỪ':'CÂU KHẲNG ĐỊNH')+'</p><div class="g-sentence">'+sentence(x,scene.focus)+'</div>';
    }else if(scene.kind==='question')out='<p class="g-board-label">ĐƯA TO BE LÊN TRƯỚC</p><div class="g-small">'+sentence(rules.examples.statement,'verb')+'</div><div class="g-contract-arrow">'+icon('arrow-down')+'</div><div class="g-sentence">'+sentence(c.examples[0],'verb')+'</div>';
    else if(scene.kind==='analysis'){
      const x=c.examples[0],equivalent=/\(=\s*([^)]*)\)/.exec(x.en)?.[1]||'',person=rules.pronouns.find(p=>p.word.toLowerCase()===equivalent.toLowerCase())?.person||'';
      out='<p class="g-board-label">XÁC ĐỊNH CHỦ NGỮ</p><p class="g-formula">'+(scene.step>=1?e(x.subject):'Chủ ngữ')+(scene.step>=2?' (= '+e(equivalent)+')':'')+(scene.step>=3?' → <strong>'+e(x.verb)+'</strong>':'')+'</p><p class="g-translation">'+(scene.step>=1?e(person):'Xác định ngôi và số trước')+'</p>';
    }
    else if(scene.kind==='repair'){
      const x=c.examples[0];out='<p class="g-board-label">'+(scene.fixed?'ĐÃ SỬA':'CÂU CẦN SỬA')+'</p><p class="g-board-error '+(scene.fixed?'fixed':'')+'">'+e(c.wrong)+'</p>'+(scene.fixed?'<div class="g-sentence">'+sentence(x,scene.focus||c.focus||'verb')+'</div>'+(scene.meaning?'<p class="g-translation">'+e(x.vi)+'</p>':''):'');
    }else if(scene.kind==='contract-guide')out='<p class="g-board-label">GRAM HƯỚNG DẪN</p><p class="g-formula">Chọn mẫu<br>↓<br>Bấm “Rút gọn”</p><p class="g-translation">Gram sẽ giảng mẫu bạn chọn.</p>';
    else if(scene.kind==='contraction'){
      const p=rules.contractions[scene.pair];out='<p class="g-board-label">'+(scene.contracted?'ĐÃ RÚT GỌN':'DẠNG ĐẦY ĐỦ')+'</p><p class="g-contract-full">'+e(p.before)+'<span class="g-removed '+(scene.contracted?'omitted':'')+'">'+e(p.removed)+'</span>'+e(p.after)+'</p><div class="g-contract-arrow">'+icon('arrow-down')+'</div><p class="g-contracted '+(scene.contracted?'shown':'')+'">'+(scene.contracted?e(p.short):'…')+'</p><p class="g-translation">'+e(p.meaning)+'</p>';
    }else if(scene.kind==='word-change'){
      const p=rules.wordChanges[scene.pair];let common=0;while(common<Math.min(p.singular.length,p.plural.length)&&p.singular[common]===p.plural[common])common++;
      const same=p.singular===p.plural;
      out='<p class="g-board-label">'+(p.uncountable?'KHÔNG ĐẾM ĐƯỢC':scene.changed?'SỐ NHIỀU':'SỐ ÍT')+'</p><div class="g-word-transform"><span>'+e(p.singular.slice(0,common))+'<span class="g-word-ending '+(scene.changed?'is-removed':'')+'">'+e(p.singular.slice(common))+'</span></span><span class="g-transform-arrow">'+icon('arrow-right')+'</span><strong class="'+(scene.changed?'shown':'pending')+'">'+(scene.changed?e(p.plural.slice(0,common))+'<span class="g-word-ending">'+e(p.plural.slice(common))+'</span>':'?')+'</strong></div><p class="g-translation">'+e(p.meaning)+(scene.changed&&same?' · Giữ nguyên hình thức':'')+'</p>';
    }else if(scene.kind==='checklist')out='<p class="g-board-label">'+(scene.active>=0?'ĐIỀU '+(scene.active+1)+' / 4':'TỰ KIỂM TRA')+'</p><p class="g-scene-info">'+e(scene.active>=0?c.checks[scene.active]:'Bốn điều trước khi làm bài')+'</p>';
    return out;
  }
  function contractionPanel(){
    return '<section class="g-contraction-controls"><label for="g-pair">Chọn mẫu để Gram giải thích</label><div class="g-contract-row"><select id="g-pair" aria-label="Mẫu rút gọn">'+rules.contractions.map((p,i)=>'<option value="'+i+'" '+(i===state.pair?'selected':'')+'>'+e(p.full)+' ('+e(p.meaning)+')</option>').join('')+'</select><button type="button" class="g-btn g-primary" data-action="contract">'+(state.contracted?'Tách ra':'Rút gọn')+icon(state.contracted?'move-horizontal':'volume-2')+'</button></div><p class="g-contract-note">'+(state.pair===rules.specialContraction.pair?'<s>'+e(rules.specialContraction.wrong)+'</s> · Dùng <strong>'+e(rules.specialContraction.short)+'</strong> trong mẫu đang học.':'Bấm Rút gọn để nghe Gram đọc và giảng mẫu này.')+'</p></section>';
  }
  function lockedPanel(){return '<p class="g-interaction-lock" role="status">'+icon('lock-keyhole')+'<span>'+(state.lectureStarted||state.pairSpeaking?'Gram đang giảng · tương tác tạm khóa':'Nghe Gram giảng xong để mở tương tác')+'</span></p>'}
  function wordChangePanel(){
    const uncountable=rules.wordChanges[state.pair]?.uncountable;
    return '<section class="g-contraction-controls"><label for="g-word-change">Chọn từ để xem và nghe cách đổi dạng</label><div class="g-contract-row"><select id="g-word-change" aria-label="Danh từ cần đổi dạng">'+card().wordChangeIDs.map(i=>{const p=rules.wordChanges[i];return '<option value="'+i+'" '+(i===state.pair?'selected':'')+'>'+e(p.singular)+' ('+e(p.meaning)+')</option>'}).join('')+'</select><button type="button" class="g-btn g-primary" data-action="word-change">'+(uncountable?(state.contracted?'Đặt lại':'Xem cách dùng'):state.contracted?'Xem số ít':'Xem số nhiều')+icon(state.contracted?'rotate-ccw':'volume-2')+'</button></div></section>';
  }

  function practicePanel(){
    const c=card(),open=unlocked();if(!open)return lockedPanel();
    if(canMatch())return matchingPanel();
    if(c.kind==='contraction')return '<div class="g-practice">'+contractionPanel()+'</div>';
    if(c.kind==='word-change')return '<div class="g-practice">'+wordChangePanel()+'</div>';
    if(c.kind==='checklist')return '<div class="g-practice g-check-list">'+c.checks.map(t=>'<label><input type="checkbox"><span>'+e(t)+'</span></label>').join('')+'</div>';
    let out='';
    if(c.examples.length>1)out+='<div class="g-example-picks">'+c.examples.map((_,i)=>'<button type="button" data-example="'+i+'" aria-pressed="'+((currentScene().example??state.example)===i)+'">Ví dụ '+(i+1)+'</button>').join('')+'</div>';
    if(c.kind==='example')out+='<div class="g-analysis-tabs">'+[['meaning','Nghĩa'],['structure','Cấu trúc'],['context','Ngữ cảnh']].map(([v,label])=>'<button type="button" data-tab="'+v+'" aria-pressed="'+(state.tab===v)+'">'+label+'</button>').join('')+'</div>';
    if(['negative','question'].includes(c.kind))out+='<button type="button" data-action="compare">'+(c.kind==='negative'?(state.compare?'Thêm not (không)':'Bỏ not (không)'):(state.compare?'Đổi thành câu hỏi':'Đổi thành câu kể'))+'</button>';
    if(c.kind==='repair')out+='<button type="button" data-action="reveal">'+(state.revealed?'Đã sửa đúng':'Xem cách sửa')+'</button>';
    if(c.wordChangeIDs?.length)out+=wordChangePanel();
    const scene=currentScene(),hasSentence=['example','negative','question'].includes(scene.kind)||scene.kind==='repair'&&scene.fixed;return (out?'<div class="g-practice">'+out+'</div>':'')+(hasSentence?roleHelpView():'');
  }
  function roleHelpText(){return roleHelp[state.role]||(rules.wordHint||'Chạm vào chủ ngữ, to be hoặc bổ ngữ trên bảng để xem chú thích.')}
  function roleHelpView(){return '<p class="g-role-help '+(!state.role?'is-hint':'')+'" role="status" aria-live="polite">'+e(roleHelpText())+'</p>'}
  function theoryBody(scene){
    const c=card(),x=sceneExample(scene)||displayExample();
    const followCaption=state.demoPair!==null||state.lectureStarted&&!state.lectureDone||c.keepFinalCaption&&state.lectureDone&&!state.practiceBoard&&voiceTrack===partKey();
    if(c.syncCaptions&&followCaption&&typeof scene.caption==='string')return scene.caption;
    return c.kind==='example'?(state.tab==='meaning'?x?.vi:state.tab==='context'?c.context:c.body):c.body;
  }
  function theoryNoteVisible(scene){const c=card(),follows=c.syncCaptions&&(state.demoPair!==null||state.lectureStarted&&!state.lectureDone||c.keepFinalCaption&&state.lectureDone&&!state.practiceBoard&&voiceTrack===partKey());return Boolean(c.note)&&!(follows&&scene.isNote)}
  function theoryView(){
    const c=card(),scene=currentScene(),body=theoryBody(scene);
    return toolbar('Lý thuyết',c.group,'topic',icon('list')+partCount+' phần','parts')+'<div class="g-learning '+(canMatch()||c.kind==='checklist'?'is-dense':c.kind==='example'?'is-example':'')+'"><div class="g-theory-top"><div class="g-part-progress" aria-label="Phần '+(state.part+1)+' trên '+partCount+'"><span style="width:'+(state.part+1)/partCount*100+'%"></span></div><div class="g-card-heading"><div><p class="g-kicker">PHẦN '+(state.part+1)+' / '+partCount+'</p><h2>'+e(c.title)+'</h2></div>'+(state.progress.read[c.id]?'<span>'+icon('circle-check')+'Đã học</span>':'')+'</div><section class="g-classroom" aria-label="Gram và bảng minh họa"><div class="g-teacher-stage">'+actorMount()+'<div class="g-podium" aria-hidden="true"></div></div><div class="g-board">'+boardView(scene)+'</div></section><section class="g-source-card"><p class="g-source-text">'+e(body)+'</p>'+(c.formula?'<p class="g-formula">'+e(c.formula)+'</p>':'')+(c.note?'<p class="g-small g-source-note" '+(theoryNoteVisible(scene)?'':'hidden')+'>'+e(c.note)+'</p>':'')+'</section></div><section class="g-theory-middle" aria-label="Tương tác bài học">'+practicePanel()+'</section><footer class="g-theory-bottom">'+audioView()+'<p class="g-reading-progress">Đã học '+readCount()+'/'+partCount+' phần</p></footer></div>';
  }
  function audioView(){
    const track=activeTrack();
    return '<section class="g-audio" aria-label="Điều khiển lời giảng"><span class="g-audio-language g-sr">Sẵn sàng giảng</span><div class="g-seek-row"><span class="g-current-time">0:00</span><input type="range" class="g-seek" min="0" max="'+track.audioInfo.duration+'" step="0.1" value="0" aria-label="Tua lời giảng của phần này"><span>'+fmt(track.audioInfo.duration)+'</span></div><div class="g-lesson-bar"><button type="button" class="g-icon-btn" data-action="previous-part" aria-label="Phần trước" '+(state.part===0?'disabled':'')+'>'+icon('arrow-left')+'</button><div class="g-audio-cluster" aria-label="Bản ghi âm lời giảng"><button type="button" class="g-icon-btn g-replay" data-action="replay" aria-label="Nghe lại">'+icon('rotate-ccw')+'</button><button type="button" class="g-icon-btn g-play" data-action="play" aria-label="Nghe giảng" aria-pressed="false">'+icon('play')+'<span class="g-play-label">Nghe giảng</span></button><select class="g-rate" aria-label="Tốc độ phát"><option value="0.85">0,85×</option><option value="1">1×</option><option value="1.25">1,25×</option><option value="1.5">1,5×</option></select></div><button type="button" class="g-btn g-primary g-understood" data-action="next-part">Đã hiểu '+icon('arrow-right')+'</button></div>'+(voiceError?'<p class="g-audio-message" role="status">'+e(voiceError)+'</p>':'')+'</section>';
  }
  function matchingPanel(){
    const p=pronoun(),answer=pairAnswer(),wrong=state.verb&&state.verb!==answer;
    if(objectMatch()){
      return '<section class="g-practice g-match" aria-label="Ghép dạng chủ ngữ và tân ngữ"><p class="g-muted">Chọn dạng chủ ngữ, rồi chọn dạng tân ngữ tương ứng.</p><div class="g-pronouns">'+rules.pronouns.map(v=>'<button type="button" data-pronoun="'+e(v.word)+'" aria-pressed="'+(p.word===v.word)+'">'+e(v.word)+'</button>').join('')+'</div><div class="g-object-choices">'+rules.pronouns.map(v=>v.object).filter((v,i,a)=>a.indexOf(v)===i).map(v=>'<button type="button" class="g-verb-choice '+(state.verb===v?(v===answer?'is-correct':'is-wrong'):'')+'" data-verb="'+e(v)+'" aria-pressed="'+(state.verb===v)+'">'+e(v)+'</button>').join('')+'</div><p class="g-match-help '+(wrong?'wrong':'')+'" data-state="'+(state.verb?(wrong?'wrong':'correct'):'unselected')+'" role="status">'+(state.verb?(wrong?'Thử lại: ':'Đúng rồi! ')+e(p.word)+' chuyển sang dạng tân ngữ là '+e(answer)+'.':e(p.word)+' ('+e(p.vi)+') · '+e(p.person)+'.')+'</p></section>';
    }
    return '<section class="g-practice g-match" aria-label="Ghép chủ ngữ và to be"><p class="g-muted">Chọn chủ ngữ, rồi chọn dạng to be (là, thì, ở).</p><div class="g-pronouns">'+rules.pronouns.map(v=>'<button type="button" data-pronoun="'+e(v.word)+'" aria-pressed="'+(p.word===v.word)+'">'+v.word+'</button>').join('')+'</div><div class="g-verb-row"><span>Đi cùng</span>'+['am','is','are'].map(v=>'<button type="button" class="g-verb-choice '+(state.verb===v?(v===p.verb?'is-correct':'is-wrong'):'')+'" data-verb="'+v+'" aria-pressed="'+(state.verb===v)+'">'+v+'</button>').join('')+'</div><p class="g-match-help '+(wrong?'wrong':'')+'" data-state="'+(state.verb?(wrong?'wrong':'correct'):'unselected')+'" role="status">'+(state.verb?(wrong?'Thử lại: ':'Đúng rồi! ')+e(p.word)+' là '+e(p.person)+', đi với '+e(p.verb)+'.':e(p.word)+' ('+e(p.vi)+') · '+e(p.person)+'.')+'</p></section>';
  }
    function markCurrent(){if(!state.progress.read[card().id]){state.progress.read[card().id]=true;persist()}}
  async function showPart(index,{autoplay=false}={}){if(!Number.isInteger(index)||index<0||index>=partCount)return;stop();voiceTrack='';state.part=index;resetInteraction();state.view='theory';voiceError='';actor.setChapter(index);render();persist();if(autoplay)await play(true)}
  async function nextPart(){
    markCurrent();
    if(state.part<partCount-1)return showPart(state.part+1,{autoplay:true});
    const missing=ids.findIndex(id=>!state.progress.read[id]);
    if(missing>=0)return showPart(missing,{autoplay:true});
    stop();state.view='topic';toast='Đã học xong lý thuyết. Bài tập Dễ đã mở!';render();persist();announce(toast);
  }
  async function trackURL(track){
    const key=track.audioInfo.audioFile;
    if(!audioBlobs.has(key)){
      const pending=window.gramNative.loadAudio(key).then(payload=>{
        if(payload.version!==data.releaseID||payload.key!==key||payload.mimeType!=='audio/mpeg')throw Error('Lời giảng chưa khớp phiên bản.');
        const raw=atob(payload.base64),bytes=new Uint8Array(raw.length);for(let i=0;i<raw.length;i++)bytes[i]=raw.charCodeAt(i);
        return URL.createObjectURL(new Blob([bytes],{type:'audio/mpeg'}));
      }).catch(error=>{audioBlobs.delete(key);throw error});
      audioBlobs.set(key,pending);
    }
    return audioBlobs.get(key);
  }
  async function ensureAudio(request=token){
    const key=state.demoPair!==null?demoKey(state.demoPair):partKey(),track=activeTrack();
    if(voiceTrack!==key){
      const url=await trackURL(track);
      if(request!==token||state.view!=='theory'||key!==(state.demoPair!==null?demoKey(state.demoPair):partKey()))return false;
      audio.src=url;voiceTrack=key;voicePart=state.part;audio.load();audio.currentTime=0;
    }
    audio.playbackRate=state.rate;actor.setChapter(state.demoPair!==null?partCount+state.demoPair:state.part);
    return true;
  }
  function syncBoard(force=false){
    if(state.view!=='theory')return;
    const currentKey=state.demoPair!==null?demoKey(state.demoPair):partKey();if(voicePart!==state.part||voiceTrack!==currentKey){updateAudioUI();return}
    const scene=currentScene(),key=JSON.stringify(scene);
    if(force||key!==lastCueKey){
      lastCueKey=key;state.role='';
      const board=q('.g-board');if(board)board.innerHTML=boardView(scene);const caption=q('.g-source-text');if(caption&&card().syncCaptions)caption.textContent=theoryBody(scene);const note=q('.g-source-note');if(note)note.hidden=!theoryNoteVisible(scene);const help=q('.g-role-help');if(help){help.textContent=roleHelpText();help.classList.add('is-hint')}
      app.querySelectorAll('[data-example]').forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.example)===(scene.example||0))));
      app.querySelectorAll('.g-check-list label').forEach((el,i)=>el.classList.toggle('g-check-active',scene.active===i));
      if(globalThis.lucide)lucide.createIcons({attrs:{width:16,height:16}});
      if(!audio.paused)actor.perform('point',650);
    }
    updateAudioUI();
  }
  async function play(replay){
    const request=++token,isDemo=state.demoPair!==null;
    const restart=replay||audio.ended||voiceTrack!==(isDemo?demoKey(state.demoPair):partKey());
    if(restart){state.role='';state.practiceBoard=false;state.revealed=false;state.compare=false;state.example=0;state.tab=defaultTheoryTab;state.verb=null;state.contracted=false}
    if(isDemo)state.pairSpeaking=true;else{state.lectureStarted=true;state.lectureDone=false}
    voiceLoading=true;voiceError='';render();
    try{
      if(!await ensureAudio(request)||request!==token)return;
      if(restart)audio.currentTime=0;
      voiceLoading=false;render();syncBoard(true);
      await audio.play();if(request!==token)return;
      voiceError='';updateAudioUI();
    }catch(error){if(request===token){voiceLoading=false;voiceError='Chưa tải được lời giảng. Bạn kiểm tra kết nối rồi bấm nghe lại nhé.';render()}}
    finally{if(request===token){voiceLoading=false;updateAudioUI()}}
  }
  function startContraction(){
    if(!unlocked())return;
    if(state.contracted){stop();state.demoPair=null;voiceTrack='';state.contracted=false;state.practiceBoard=true;render();animateBoard();return}
    state.demoPair=(card().wordChangeIDs?.length?rules.contractions.length:0)+state.pair;state.practiceBoard=false;state.role='';play(true);
  }
  function updateAudioUI(){
    if(state.view!=='theory')return;
    const key=state.demoPair!==null?demoKey(state.demoPair):partKey();
    const playing=voiceTrack===key&&!audio.paused&&!audio.ended,now=voiceTrack===key?audio.currentTime:0,button=q('.g-play');
    if(button){const status=voiceLoading?'loading':String(playing),changed=button.dataset.playing!==status;if(!changed&&performance.now()-lastUI<70)return;lastUI=performance.now();if(changed){button.dataset.playing=status;button.disabled=voiceLoading;const replay=q('.g-replay');if(replay)replay.disabled=voiceLoading;button.innerHTML=icon(playing?'pause':'play')+'<span class="g-play-label">'+(voiceLoading?'Đang tải…':playing?'Tạm dừng':'Nghe giảng')+'</span>';button.setAttribute('aria-label',playing?'Tạm dừng':'Nghe giảng');button.setAttribute('aria-pressed',String(playing));if(globalThis.lucide)lucide.createIcons({attrs:{width:16,height:16}})}}
    const current=q('.g-current-time');if(current)current.textContent=fmt(now);
    const seek=q('.g-seek');if(seek)seek.value=now;
    const rate=q('.g-rate');if(rate)rate.value=state.rate;
    const seg=activeTrack().audioInfo.segments.find(s=>now>=s.start&&now<s.end),label=q('.g-audio-language');
    if(label)label.textContent=playing?(seg?.lang==='en'?'Phát âm tiếng Anh':'Giảng bằng tiếng Việt'):audio.ended&&voiceTrack===key?'Đã nghe xong':'Có thể nghe lại';
  }
  function tick(){syncBoard();if(!audio.paused)clock=requestAnimationFrame(tick)}
  audio.addEventListener('playing',()=>{cancelAnimationFrame(clock);tick()});
  audio.addEventListener('pause',()=>{cancelAnimationFrame(clock);syncBoard()});
  audio.addEventListener('timeupdate',()=>syncBoard());
  audio.addEventListener('seeking',()=>syncBoard(true));
  audio.addEventListener('seeked',()=>syncBoard(true));
  audio.addEventListener('loadedmetadata',()=>syncBoard(true));
  audio.addEventListener('ended',()=>{
    if(state.view!=='theory'||voicePart!==state.part)return;
    if(voiceTrack!==(state.demoPair!==null?demoKey(state.demoPair):partKey()))return;
    if(state.demoPair!==null){state.pairSpeaking=false;state.contracted=true}
    else{state.lectureStarted=false;state.lectureDone=true;state.heard[card().id]=true;adoptLecturePair();markCurrent();announce('Đã giảng xong. Bạn có thể tương tác với phần này.')}
    state.practiceBoard=false;persist();render();syncBoard(true);
  });


  const answerLabel=(item,value)=>value===null||value===undefined?'Chưa trả lời':item.type==='choice'?item.options[value]??'Chưa trả lời':String(value);
  function exerciseView(){
    const item=question(),answer=state.answers[state.question],done=state.submitted,right=answer?.correct,isVi=item.prompt.startsWith('Câu dưới');
    const correctValue=item.type==='choice'?item.options[item.answer]:item.answer;
    const feedback=done?'<section class="g-inline-feedback '+(!right?'wrong':'')+'" role="status"><h3>'+icon(right?'circle-check':answer.timedOut?'timer-off':'circle-x')+(answer.timedOut?'Hết thời gian':right?'Chính xác!':'Chưa đúng rồi')+'</h3>'+(!right?'<p class="g-correct-answer">Đáp án đúng: '+e(correctValue)+'</p>':'')+'<p>'+e(item.explanation)+'</p></section>':'';
    return toolbar('Bài tập '+names[state.level],topicLabel,'topic')+'<div class="g-exercise"><div class="g-question-meta"><span class="g-pill">MỨC '+names[state.level].toLocaleUpperCase('vi')+'</span><span class="g-timer" role="timer" aria-label="Thời gian còn lại">'+icon(done?'check':'timer')+'<b class="g-countdown">'+(done?'Đã trả lời':timerFmt(rules.remaining(state.deadline)))+'</b></span><span>Câu '+(state.question+1)+' / '+questionCount()+'</span></div><div class="g-question-progress"><span style="width:'+(state.question+(done?1:0))/questionCount()*100+'%"></span></div><h2 class="g-prompt">'+e(item.prompt)+'</h2>'+(item.stem?'<p class="g-stem '+(isVi?'vi':'')+'">'+e(item.stem)+'</p>':'')+(item.meaning?'<p class="g-gloss">'+e(item.meaning)+'</p>':'')+(item.hint?'<p class="g-question-hint">Gợi ý: '+e(item.hint)+'</p>':'')+(item.type==='choice'?'<div class="g-options">'+item.options.map((option,i)=>'<button type="button" class="g-option '+(done?(i===item.answer?'correct':i===state.choice?'incorrect':''):'')+'" data-choice="'+i+'" aria-pressed="'+(state.choice===i)+'" '+(done?'disabled':'')+'><span>'+String.fromCharCode(65+i)+'</span><span>'+e(option)+'</span>'+(done&&i===item.answer?icon('circle-check'):done&&i===state.choice?icon('circle-x'):'')+'</button>').join('')+'</div>':'<label class="g-answer-label" for="g-typed">Đáp án của bạn<input id="g-typed" class="g-answer-input '+(done?(right?'correct':'incorrect'):'')+'" type="text" inputmode="text" enterkeyhint="done" autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="250" placeholder="Nhập đáp án" value="'+e(state.typed)+'" '+(done?'readonly':'')+'></label>')+'<div class="g-feedback-slot">'+feedback+(state.question===questionCount()-1&&done?'<p class="g-attempt-status" role="status">'+(completionSaving?'Đang lưu kết quả…':e(completionError))+'</p>':'')+'</div><footer class="g-exercise-footer"><button type="button" data-action="'+(done?'next-question':'check-answer')+'" class="g-btn g-primary '+(!done?'g-check-answer':'')+'" '+(completionSaving||!done&&(item.type==='choice'?state.choice===null:!state.typed.trim())?'disabled':'')+'>'+(done?(state.question===questionCount()-1?(completionSaving?'Đang lưu…':completionError?'Thử lưu lại':'Xem kết quả'):'Câu tiếp theo'):'Kiểm tra')+icon('arrow-right')+'</button></footer></div>';
  }
  function primeSound(){try{soundContext??=new (window.AudioContext||window.webkitAudioContext)();soundContext.resume().catch(()=>{})}catch(error){}}
  function soundEffect(right){
    if(!window.gramNative.effectsEnabled)return;primeSound();if(!soundContext)return;
    const at=soundContext.currentTime;
    (right?[[0,880,.32],[.08,1318.5,.42]]:[[0,190,.12],[.18,145,.16]]).forEach(([offset,freq,duration])=>{
      const osc=soundContext.createOscillator(),gain=soundContext.createGain();osc.type=right?'sine':'square';osc.frequency.setValueAtTime(freq,at+offset);if(!right)osc.frequency.exponentialRampToValueAtTime(freq*.78,at+offset+duration);
      gain.gain.setValueAtTime(.0001,at+offset);gain.gain.exponentialRampToValueAtTime(right?.11:.035,at+offset+.008);gain.gain.exponentialRampToValueAtTime(.0001,at+offset+duration);osc.connect(gain);gain.connect(soundContext.destination);osc.start(at+offset);osc.stop(at+offset+duration+.02);
    });
  }
  function makeAttemptID(){
    if(crypto.randomUUID)return crypto.randomUUID();
    const bytes=crypto.getRandomValues(new Uint8Array(16));bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;
    const hex=[...bytes].map(b=>b.toString(16).padStart(2,'0')).join('');
    return hex.slice(0,8)+'-'+hex.slice(8,12)+'-'+hex.slice(12,16)+'-'+hex.slice(16,20)+'-'+hex.slice(20);
  }
  function beginDeadline(){state.deadline=Date.now()+rules.limit(state.level,question().type)*1000}
  function startLevel(level){
    if(completionSaving||!core.unlocked(state.progress,ids,level))return;stop();state.level=level;clearAttempt();primeSound();state.activeAttempt=makeAttemptID();state.attemptStarted=Date.now();state.view='exercise';beginDeadline();render();persist();
  }
  async function finishAttempt(){
    if(completionSaving)return;
    const progress=structuredClone(state.progress);
    if(!core.finish(progress,ids,state.level,state.answers,questionCount()))return;
    pendingCompletion??={id:state.activeAttempt,lessonVersion:data.releaseID,level:state.level,duration:Math.max(1,Math.round((Date.now()-state.attemptStarted)/1000)),results:data.exercises[state.level].map((item,i)=>{
      const answer=state.answers[i];return {questionID:String(item.id||state.level+':'+(i+1)),prompt:item.prompt,stem:item.stem||'',answer:answerLabel(item,answer.value),correctAnswer:answerLabel(item,item.answer),correct:answer.correct,timedOut:answer.timedOut};
    })};
    completionSaving=true;completionError='';render();
    try{
      // One database transaction commits the immutable result and the newly earned star.
      const saved=await window.gramNative.completeAttempt(pendingCompletion,snapshot(progress));
      state.progress=core.restore(saved.snapshot?.privateContent?.gramV4?.progress||progress,ids,exerciseCounts);
      const record=saved.attempt;state.history=[record,...state.history.filter(a=>a.id!==record.id)];
      state.selectedAttempt=record.id;state.resultBack='topic';pendingCompletion=null;
      // A new attempt shifts pagination; fetch the first page again when history is opened.
      historyLoaded=false;historyOffset=0;
    }catch(error){completionError='Chưa lưu được kết quả. Bạn kiểm tra kết nối rồi thử lại nhé.'}
    finally{completionSaving=false;render();persist()}
  }
  function submit(timedOut=false){
    if(state.submitted||state.view!=='exercise')return;if(!timedOut&&Date.now()>=state.deadline)timedOut=true;
    const item=question(),value=item.type==='choice'?state.choice:state.typed;if(!timedOut&&(value===null||!String(value).trim()))return;
    const right=!timedOut&&core.grade(item,value);state.answers[state.question]={value,correct:right,timedOut};state.submitted=true;state.deadline=0;
    if(state.question===questionCount()-1)finishAttempt();soundEffect(right);render();persist();announce(timedOut?'Hết thời gian.':right?'Trả lời đúng.':'Trả lời chưa đúng.');
  }
  function updateTimer(){
    if(state.view!=='exercise'||state.submitted||!state.deadline)return;
    const remaining=rules.remaining(state.deadline),label=q('.g-countdown'),timer=q('.g-timer');if(label)label.textContent=timerFmt(remaining);if(timer){timer.classList.toggle('urgent',remaining<=10);timer.setAttribute('aria-label','Còn '+remaining+' giây')}if(remaining===0)submit(true);
  }
  function nextQuestion(){
    if(!state.submitted)return;
    if(state.question===questionCount()-1){if(completionSaving)return;if(pendingCompletion){finishAttempt();return}navigate('result');return}
    state.question++;state.choice=null;state.typed='';state.submitted=false;beginDeadline();render();persist();
  }
  const attemptScore=record=>record.score;
  const attemptPercent=record=>new Intl.NumberFormat('vi-VN',{style:'percent',maximumFractionDigits:2}).format(record.score/record.results.length);
  const attemptPassed=record=>core.passed(record.level,record.score,record.results.length);
  const requirement=level=>'Cần đúng '+(level==='hard'?'100%':'trên 80%')+' số câu';
  async function loadHistory(reset=false){
    if(historyLoading)return;historyLoading=true;historyError='';render();
    try{
      const page=await window.gramNative.loadHistory(reset?0:historyOffset);
      state.history=reset?page.items:[...state.history,...page.items.filter(a=>!state.history.some(b=>b.id===a.id))];
      historyOffset=(reset?0:historyOffset)+page.items.length;historyMore=page.hasMore;historyLoaded=true;
    }catch(error){historyError='Chưa tải được lịch sử. Bạn kiểm tra kết nối rồi thử lại nhé.'}
    finally{historyLoading=false;if(state.view==='history')render()}
  }
  function historyView(){
    const status=historyError?'<div class="g-history-status" role="status"><p>'+e(historyError)+'</p><button type="button" class="g-btn" data-action="reload-history">Thử lại</button></div>':historyLoading?'<p class="g-history-status" role="status">Đang tải lịch sử…</p>':'';
    return toolbar('Lịch sử làm bài',topicLabel)+'<div class="g-history-page"><div class="g-history-heading"><h2>Các lần đã hoàn thành</h2><p>'+state.history.length+(historyMore?'+':'')+' lần</p></div>'+status+(state.history.length?'<div class="g-scroll g-history-list">'+state.history.map(record=>'<button type="button" class="g-attempt-card" data-attempt="'+e(record.id)+'"><span class="g-attempt-icon">'+icon('clipboard-check')+'</span><span class="g-attempt-copy"><strong>Mức '+names[record.level]+'</strong><small>'+dateLabel(record.at)+'</small><small>'+fmt(record.duration)+' · '+record.score+' câu đúng</small><span class="g-history-verdict"><strong>'+attemptPercent(record)+' câu đúng</strong><span class="g-result-status" data-passed="'+attemptPassed(record)+'">'+(attemptPassed(record)?'Đạt':'Chưa đạt')+'</span></span></span><span class="g-score-number">'+record.score+'/'+record.results.length+'</span>'+icon('chevron-right')+'</button>').join('')+(historyMore?'<button type="button" class="g-btn g-load-more" data-action="more-history" '+(historyLoading?'disabled':'')+'>Tải thêm</button>':'')+'</div>':historyLoaded&&!historyError?'<div class="g-empty">'+icon('history')+'<h2>Chưa có lịch sử</h2><p>Hoàn thành một mức bài tập để xem kết quả tại đây.</p></div>':'')+'</div>';
  }
  function resultView(){
    const record=state.history.find(a=>a.id===state.selectedAttempt);if(!record)return historyView();
    const score=record.score,passed=attemptPassed(record),levelStars=passed?core.levels.indexOf(record.level)+1:0;
    return toolbar('Kết quả mức '+names[record.level],dateLabel(record.at),state.resultBack)+'<div class="g-results-page"><section class="g-result-summary"><div><div class="g-score-number">'+score+'<span class="g-muted">/'+record.results.length+'</span></div><p class="g-result-verdict"><strong class="g-result-percent">'+attemptPercent(record)+' câu đúng</strong><span class="g-result-status" data-passed="'+passed+'">'+(passed?'Đạt':'Chưa đạt')+'</span></p><p>'+fmt(record.duration)+' · '+requirement(record.level)+'</p></div><div><div class="g-stars" aria-label="'+levelStars+' sao">'+starText(levelStars)+'</div><p>'+score+' đúng · '+(record.results.length-score)+' chưa đúng</p></div></section><div class="g-scroll g-result-list">'+record.results.map((item,i)=>{
      return '<section class="g-result-row '+(!item.correct?'wrong':'')+'">'+icon(item.correct?'circle-check':'circle-x')+'<div><small>Câu '+String(i+1).padStart(2,'0')+' · '+(item.correct?'Đúng':item.timedOut?'Hết giờ':'Chưa đúng')+'</small><strong>'+e(item.stem||item.prompt)+'</strong><p class="g-user-answer">'+(item.correct?'':item.timedOut?'Chưa trả lời · ':'Bạn: ')+e(item.timedOut?'Hết thời gian':item.answer)+'</p>'+(!item.correct?'<p class="g-correction">Đúng: '+e(item.correctAnswer)+'</p>':'')+'</div></section>';
    }).join('')+'</div><footer class="g-result-bottom"><button type="button" class="g-btn" data-action="history">'+icon('history')+'Lịch sử</button><button type="button" class="g-btn g-primary" '+(passed?'data-action="topic"':'data-level="'+record.level+'"')+'>'+(passed?'Về chủ điểm':'Làm lại')+'</button></footer></div>';
  }
  app.addEventListener('keydown',event=>{if(event.key==='Enter'&&!event.isComposing&&event.target.id==='g-typed'){event.preventDefault();submit()}});
  app.addEventListener('input',async event=>{
    if(event.target.id==='g-typed'){state.typed=event.target.value;const button=q('.g-check-answer');if(button)button.disabled=!state.typed.trim()}
    if(event.target.classList.contains('g-seek')){const at=Number(event.target.value);if(state.demoPair!==null)state.pairSpeaking=true;else{state.lectureStarted=true;state.lectureDone=false}state.practiceBoard=false;state.role='';const request=++token;try{if(await ensureAudio(request)&&request===token){audio.currentTime=at;actor.refresh();syncBoard(true)}}catch(error){if(request===token){voiceError='Chưa tải được lời giảng. Bạn thử nghe lại nhé.';render()}}}
  });
  app.addEventListener('change',event=>{
    if(event.target.classList.contains('g-rate')){state.rate=Number(event.target.value);audio.playbackRate=state.rate;persist()}
    if(['g-pair','g-word-change'].includes(event.target.id)&&unlocked()){stop();state.pair=Number(event.target.value);state.demoPair=null;voiceTrack='';state.contracted=false;state.practiceBoard=true;state.wordChangePractice=event.target.id==='g-word-change';state.role='';actor.perform('point',1000);render();persist()}
  });
  function animateBoard(){if(!matchMedia('(prefers-reduced-motion: reduce)').matches)q('.g-board')?.animate([{transform:'translateY(3px)'},{transform:'translateY(0)'}],{duration:200,easing:'ease-out'})}
  app.addEventListener('click',event=>{
    const b=event.target.closest('button');if(!b||b.disabled)return;
    if(b.dataset.part!==undefined){showPart(Number(b.dataset.part));return}
    if(b.dataset.level){startLevel(b.dataset.level);return}
    if(b.dataset.attempt){state.selectedAttempt=b.dataset.attempt;state.resultBack='history';navigate('result');return}
    if(b.dataset.pronoun){if(!unlocked())return;state.practiceBoard=true;state.role='';state.pronoun=b.dataset.pronoun;state.verb=null;actor.perform('point',1000);render();animateBoard();return}
    if(b.dataset.verb){if(!unlocked())return;state.practiceBoard=true;state.role='';state.verb=b.dataset.verb;actor.perform(state.verb===pairAnswer()?'wink':'point',1000);render();animateBoard();return}
    if(b.dataset.choice!==undefined){if(state.submitted)return;if(Date.now()>=state.deadline){submit(true);return}state.choice=Number(b.dataset.choice);app.querySelectorAll('.g-option').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));q('.g-check-answer').disabled=false;return}
    if(b.dataset.role){if(!unlocked())return;state.role=b.dataset.role;actor.perform('point',800);render();return}
    if(b.dataset.example!==undefined){if(!unlocked())return;stop();state.demoPair=null;voiceTrack='';state.practiceBoard=true;state.wordChangePractice=false;state.role='';state.example=Number(b.dataset.example);actor.perform('point',800);render();return}
    if(b.dataset.tab){if(!unlocked())return;state.example=currentScene().example??state.example;stop();state.demoPair=null;voiceTrack='';state.practiceBoard=true;state.wordChangePractice=false;state.tab=b.dataset.tab;render();return}
    const action=b.dataset.action;if(!action)return;if(action==='exit'){if(completionSaving){showToast('Đang lưu kết quả…');return}stop();clearAttempt();persist();window.gramNative.exit();return}if(action==='reload-history'){loadHistory(!historyLoaded);return}if(action==='more-history'){loadHistory();return}
    if(action==='play'){if(audio.paused||voicePart!==state.part)play(false);else audio.pause();return}
    if(action==='replay'){play(true);return}
    if(action==='check-answer'){submit();return}
    if(action==='next-question'){nextQuestion();return}
    if(action==='next-part'){nextPart();return}
    if(action==='previous-part'){if(state.part>0)showPart(state.part-1);return}
    if(action==='contract'){startContraction();return}
    if(action==='word-change'){startContraction();return}
    if(action==='compare'){if(!unlocked())return;state.practiceBoard=true;state.role='';state.compare=!state.compare;actor.perform('point',900);render();animateBoard();return}
    if(action==='reveal'){if(!unlocked())return;state.practiceBoard=true;state.revealed=true;actor.perform('point',800);render();animateBoard();return}
    if(action==='learn'){showPart(complete()?0:Math.max(0,ids.findIndex(id=>!state.progress.read[id])));return}
    if(action==='list-next'||action==='list-previous'){state.listPage=Math.max(0,Math.min(partPages-1,state.listPage+(action==='list-next'?1:-1)));render();persist();return}
    if(action==='parts'){state.listPage=Math.floor(state.part/9);navigate('parts');return}
    if(['topic','history','result'].includes(action))navigate(action);
  });
  // Native app gestures: lesson text cannot be selected, dragged or magnified.
  ['gesturestart','gesturechange','gestureend'].forEach(name=>root.addEventListener(name,event=>event.preventDefault(),{passive:false}));
  root.addEventListener('touchmove',event=>{if(event.touches.length>1)event.preventDefault()},{passive:false});
  root.addEventListener('contextmenu',event=>event.preventDefault());
  root.addEventListener('selectstart',event=>{if(!event.target.matches('input,textarea'))event.preventDefault()});
  root.addEventListener('dragstart',event=>event.preventDefault());
  root.addEventListener('wheel',event=>{if(event.ctrlKey)event.preventDefault()},{passive:false});
  const timerInterval=setInterval(updateTimer,250);
  document.addEventListener('visibilitychange',()=>{if(document.hidden)stop();else updateTimer()});
  window.gramPause=()=>{stop();persist()};
  window.gramLeave=()=>{stop();clearAttempt();state.view='topic';persist()};
  window.addEventListener('pagehide',()=>{window.gramLeave();clearInterval(timerInterval);audioBlobs.forEach(promise=>promise.then(url=>URL.revokeObjectURL(url),()=>{}));audioBlobs.clear();actor.destroy();soundContext?.close().catch(()=>{})});
  applyAppearance();render();
})();
