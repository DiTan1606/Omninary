/* Shared grammar progression: easy/medium >80%, hard 100%. */
(function(scope){
 'use strict';
 const levels=['easy','medium','hard'];
 const normalize=value=>String(value??'').normalize('NFKC').trim().toLowerCase().replace(/[.!?]+$/,'').replace(/\s+/g,' ');
 function fresh(){return{read:{},done:{easy:false,medium:false,hard:false},best:{easy:0,medium:0,hard:0}}}
 function theoryDone(progress,ids){return ids.length>0&&ids.every(id=>progress.read[id]===true)}
 function unlocked(progress,ids,level){const i=levels.indexOf(level);return i>=0&&theoryDone(progress,ids)&&(i===0||progress.done[levels[i-1]]===true)}
 function stars(progress){return progress.done.easy?(progress.done.medium?(progress.done.hard?3:2):1):0}
 function grade(question,answer){return question.type==='choice'?Number.isInteger(answer)&&answer===question.answer:normalize(answer)===normalize(question.answer)}
 function required(level,count){return level==='hard'?count:Math.floor(count*80/100)+1}
 function passed(level,score,count){return levels.includes(level)&&Number.isInteger(count)&&count>0&&Number.isInteger(score)&&score>=0&&score<=count&&(level==='hard'?score===count:score*100>count*80)}
 function finish(progress,ids,level,answers,count){
   if(!Number.isInteger(count)||count<1||count>500||!unlocked(progress,ids,level)||answers.length!==count||answers.some(a=>!a||typeof a.correct!=='boolean'))return false;
   const score=answers.filter(a=>a.correct&&!a.timedOut).length;
   if(passed(level,score,count))progress.done[level]=true;
   progress.best[level]=Math.max(progress.best[level]||0,score);return true;
 }
 function restore(raw,ids,counts={}){
   const p=fresh();if(!raw||typeof raw!=='object')return p;
   ids.forEach(id=>{if(raw.read?.[id]===true)p.read[id]=true});
   for(const level of levels){if(unlocked(p,ids,level)&&raw.done?.[level]===true)p.done[level]=true;p.best[level]=Math.max(0,Math.min(counts[level]||500,Number(raw.best?.[level])||0))}
   return p;
 }
 const api={levels,normalize,fresh,theoryDone,unlocked,stars,grade,required,passed,finish,restore};scope.GramCourse=api;
 if(typeof module!=='undefined'&&module.exports)module.exports=api;
})(globalThis);
