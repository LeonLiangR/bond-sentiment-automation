import test from'node:test';import assert from'node:assert/strict';
import{makeNarrative,summarize}from'../src/core.mjs';
test('汇报只写当日，平估值为零时省略该项',()=>{
 const summary=summarize([{spread:-12},{spread:3},{spread:14}]);
 const result=makeNarrative('2026-11-12',summary);
 assert.doesNotMatch(result,/上一有效|发行定价情绪|平估值发行/);
 assert.match(result,/低估值10BP及以上1只；高估值发行2只，偏离3—14BP。/);
});
test('有平估值样本时保留只数',()=>{
 const summary=summarize([{spread:-4},{spread:0},{spread:5}]);
 assert.match(makeNarrative('2026-11-12',summary),/低估值10BP及以上0只；平估值发行1只；高估值发行1只/);
});
