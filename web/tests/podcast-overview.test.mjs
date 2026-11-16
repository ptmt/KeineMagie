import test from 'node:test';
import assert from 'node:assert/strict';
import * as core from '../core.mjs';

test('overview keeps at most the latest three episodes per feed with stable undated fallback',()=>{
  const episodes=[{id:'missing'},{id:'old',published:'2025-01-01'},{id:'new',published:'2026-11-16'},{id:'tie',published:'2026-11-16'},{id:'bad',published:'no date'}];
  assert.equal(typeof core.latestPodcastEpisodes,'function');
  assert.deepEqual(core.latestPodcastEpisodes({episodes}).map(e=>e.id),['new','tie','old']);
  assert.deepEqual(episodes.map(e=>e.id),['missing','old','new','tie','bad']);
  for(const n of [0,1,3])assert.equal(core.latestPodcastEpisodes({episodes:episodes.slice(0,n)}).length,n);
  assert.deepEqual(core.latestPodcastEpisodes({episodes:[{id:'b'},{id:'a'}]}).map(e=>e.id),['b','a']);
});

test('unprepared episode titles use an exact feed-scoped action route without starting preparation',()=>{
  assert.deepEqual(core.parsePodcastRoute('#podcasts/feed/Feed_A?episode=Same_ID'),{kind:'feed',id:'Feed_A',episodeID:'Same_ID'});
  for(const hash of ['#podcasts/feed/Feed_A?episode=../x','#podcasts/job/Job_A?episode=e','#podcasts/feed/Feed_A?episode=%2f'])assert.equal(core.parsePodcastRoute(hash).kind,'invalid');
});
