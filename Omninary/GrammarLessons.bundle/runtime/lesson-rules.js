// Shared behavior only. Pronouns, examples and contraction teaching data come from the pinned manifest.
(function(scope){
  'use strict';
  const seconds={easy:{fill:60,choice:45},medium:{fill:45,choice:30},hard:{fill:30,choice:20}};
  const api={seconds,limit:(level,type)=>seconds[level][type],remaining:(deadline,now=Date.now())=>Math.max(0,Math.ceil((deadline-now)/1000)),appearanceAt:hour=>hour>=6&&hour<18?'light':'dark'};
  scope.GramLessonRules=api;if(typeof module!=='undefined')module.exports=api;
})(typeof window!=='undefined'?window:globalThis);
