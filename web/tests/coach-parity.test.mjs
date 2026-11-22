import test from 'node:test';
import assert from 'node:assert/strict';
import {fixture} from './coach-mount-fixture.mjs';
test('task stays neutral and immutable; literal submitted answer and assessment are separate messages',async()=>{
 const turn={id:'exercise',kind:'cloze',state:'completed',message:'Complete the sentence.',prompt:'Ich warte ___ den Bus.',attempt:{id:'a',answer:'  für\n🙂  ',assessment_state:'completed',outcome:'wrong',assessment:{verdict:'incorrect',corrected_answer:'auf'}},explanation:'Warten auf.'};
 const f=fixture({snapshot:{turns:[turn],observations:[]}});f.controller.identity(f.session);await f.show();
 const task=f.messages.querySelectorAll('[data-turn]').find(e=>e.dataset.turn==='exercise');
 assert.equal(task.querySelector('.coach-prompt').textContent,turn.prompt);
 assert.ok(!task.className.includes('coach-incorrect'));
 assert.equal(f.messages.querySelector('.coach-answer').textContent,turn.attempt.answer);
 assert.ok(f.messages.querySelector('.coach-answer').className.includes('coach-user'));
 const result=f.messages.querySelector('.coach-assessment');assert.ok(result);assert.ok(result.className.includes('coach-incorrect'));assert.doesNotMatch(task.textContent,/Warten auf/);
});
