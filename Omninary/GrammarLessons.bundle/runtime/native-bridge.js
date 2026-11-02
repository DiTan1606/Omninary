(()=>{
  'use strict';
  let theme=window.gramInitialTheme||{},state=window.gramInitialState||{},effectsEnabled=window.gramEffectsEnabled!==false;
  const send=message=>window.webkit?.messageHandlers?.grammar?.postMessage(message);
  const request=message=>{
    const handler=window.webkit?.messageHandlers?.grammarHistory;
    return handler?handler.postMessage(message):Promise.reject(new Error('Chưa kết nối được dữ liệu bài học.'));
  };
  // Preserve the pre-keyboard layout, including header, question, translation and input.
  // The native host also ignores keyboard avoidance so opening it cannot shift the page.
  let layoutWidth=0,layoutHeight=0;
  function syncViewport(){
    const root=document.getElementById('gram-iphone-v4');if(!root)return;
    const width=window.innerWidth,height=Math.min(window.innerHeight,window.visualViewport?.height||window.innerHeight);
    if(width!==layoutWidth){layoutWidth=width;layoutHeight=window.innerHeight}
    else layoutHeight=Math.max(layoutHeight,window.innerHeight);
    const exercise=root.dataset.screen==='exercise';
    if(height>0)root.style.setProperty('--g-viewport-height',(exercise?layoutHeight:height)+'px');
    root.style.setProperty('--g-keyboard-lift','0px');
    if(exercise&&height<layoutHeight){
      const input=root.querySelector('#g-typed'),footer=root.querySelector('.g-exercise-footer');
      if(input&&footer){
        const action=footer.getBoundingClientRect(),answer=input.getBoundingClientRect();
        const lift=Math.max(0,action.bottom-height+8);
        // Never place the action over the unchanged question or answer field.
        if(answer.bottom+8<=action.top-lift)root.style.setProperty('--g-keyboard-lift',lift+'px');
      }
    }
    if(!['history','result'].includes(root.dataset.screen)&&(window.scrollX||window.scrollY))window.scrollTo(0,0);
  }
  window.addEventListener('error',event=>send({type:'failure',detail:event.message}));
  window.addEventListener('unhandledrejection',()=>send({type:'failure'}));
  window.gramNative={
    get state(){return state},
    get effectsEnabled(){return effectsEnabled},
    setEffectsEnabled(value){effectsEnabled=Boolean(value)},
    saveState(value){state=value;send({type:'progress',payload:value});return Promise.resolve()},
    loadAudio(key){return request({type:'audio',key,version:window.gramCourseData.releaseID})},
    loadHistory(offset=0){return request({type:'load',offset})},
    completeAttempt(attempt,snapshot){return request({type:'complete',attempt,snapshot})},
    screenChanged(screen){send({type:'screen',screen});syncViewport()},
    focusAnswer(key){
      if(window.webkit?.messageHandlers?.grammar)send({type:'focus-answer',key});
      else window.gramFocusAnswer?.({key});
    },
    exit(){window.gramLeave?.();send({type:'exit'})},
    applyTheme(){
      const root=document.getElementById('gram-iphone-v4');if(!root)return;
      root.style.colorScheme=theme.night?'dark':'light';
      root.dataset.appearance=theme.night?'dark':'light';
      for(const [key,value] of Object.entries(theme.colors||{}))root.style.setProperty('--g-'+key,value);
      const paper=theme.colors?.paper||(theme.night?'#10142A':'#EEF3FB');
      root.style.setProperty('--g-paper',paper);
      document.documentElement.style.backgroundColor=paper;
      document.body.style.backgroundColor=paper;
    },
    setTheme(value){theme=value;this.applyTheme()}
  };
  document.addEventListener('DOMContentLoaded',()=>{window.gramNative.applyTheme();syncViewport();send({type:'ready'})});
  window.addEventListener('resize',syncViewport);
  window.visualViewport?.addEventListener('resize',syncViewport);
  window.visualViewport?.addEventListener('scroll',syncViewport);
  window.addEventListener('pagehide',()=>window.gramPause?.());
})();
