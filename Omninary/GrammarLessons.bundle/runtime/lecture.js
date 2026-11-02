(function(scope){
 'use strict';
 function sceneAt(track,time){
  let index=0;
  for(const cue of track.audioInfo.cues||[]){if(time+0.001<cue.at)break;index=cue.scene}
  return track.scenes[index]||track.scenes[0];
 }
 function tokens(example){
  if(Array.isArray(example.tokens)&&example.tokens.map(t=>t.text).join('')===example.en)return example.tokens;
  const text=example.en,ranges=[];
  const add=(start,end,role)=>{if(start>=0&&!ranges.some(r=>start<r.end&&end>r.start))ranges.push({start,end,role})};
  if(example.subject){const at=text.toLowerCase().indexOf(example.subject.toLowerCase());add(at,at+example.subject.length,'subject')}
  for(const match of text.matchAll(/\b(?:am|is|are)(?:n['’]t)?\b|['’](?:m|re|s)\b/gi))add(match.index,match.index+match[0].length,'verb');
  for(const match of text.matchAll(/\bnot\b/gi))add(match.index,match.index+match[0].length,'negative');
  for(const match of text.matchAll(/\b(?:it|I)\b/gi))add(match.index,match.index+match[0].length,'subject');
  ranges.sort((a,b)=>a.start-b.start);
  const result=[];
  function gap(str){
   for(const piece of str.split(/(\band\b|\bNo\b|[.!?,;—→]+)/g)){
    if(!piece)continue;
    const found=/^\s*(.*?)\s*$/.exec(piece),word=found[1];
    if(/[A-Za-z]/.test(word)&&!['and','No'].includes(word)){
     const start=piece.indexOf(word);if(start)result.push({text:piece.slice(0,start)});
     result.push({text:word,role:'complement'});if(start+word.length<piece.length)result.push({text:piece.slice(start+word.length)});
    }else result.push({text:piece});
   }
  }
  let at=0;
  for(const range of ranges){gap(text.slice(at,range.start));result.push({text:text.slice(range.start,range.end),role:range.role});at=range.end}
  gap(text.slice(at));return result;
 }
 const api={sceneAt,tokens};scope.GramLecture=api;if(typeof module!=='undefined')module.exports=api;
})(typeof window!=='undefined'?window:globalThis);
