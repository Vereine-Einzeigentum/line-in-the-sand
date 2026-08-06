%% Harness FLUX state -- fluent calculus representation
%% Each line is a fluent in the state.

fluent(correction(1,partial,"Phase 1 failed INV-1/INV-2 on 5 prior claims. Rewrote all as input-grounded. Phase 1 gate was replace, meaning Phase 2 starts fresh. Learned assessment predicted bad. Phase 2 tightens provenance and raises abstraction level.",0.3)).
fluent(prediction(pred2,"This plan will validate because all claims are input-grounded, all four required modes for a decision action are attested with artifacts referencing real inputs.",0.9,"Validator reports ungrounded claims, missing modes, or structural issues.")).
fluent(action(act1,decision,[c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13,c14,c15,c16,c17,c18,c19,c20,c21,c22,c23,c24])).
fluent(artifact(a4,counterfactual,[i4,i8,i10])).
fluent(attested_mode(counterfactual,a4)).
fluent(artifact(a3,abduction,[i4,i13,i15])).
fluent(attested_mode(abduction,a3)).
fluent(artifact(a2,evaluation,[i4,i5,i7,i8,i15])).
fluent(attested_mode(evaluation,a2)).
fluent(artifact(a1,perception,[i1,i2,i4,i5,i6,i7,i8,i9,i10,i11,i12,i13,i14,i15])).
fluent(attested_mode(perception,a1)).
fluent(claim(c24,"The learned assessment predicted bad despite pass+replace. Phase 2 should be tighter.",inference([c23,c18]))).
fluent(claim(c23,"Phase 1 was gated with replace because 5 claims were lazily grounded in priors instead of in the docs.",input(i15))).
fluent(claim(c22,"The web layer subscribes to PubSub topics from line_core. Can be built incrementally.",inference([c13,c14,c15]))).
fluent(claim(c21,"Character data are properties on objects. They need the object graph for storage but not the dispatcher for definition.",inference([c9,c10,c11,c12,c2]))).
fluent(claim(c20,"Containment depends on objects and the dispatcher. Independent of character mechanics.",inference([c5,c7,c8,c4]))).
fluent(claim(c19,"Verb dispatch depends on objects but NOT on character mechanics, containment specifics, or the web layer.",inference([c3,c6,c1]))).
fluent(claim(c18,"The object graph has zero dependencies on other subsystems. It is the base layer.",inference([c2,c5,c13]))).
fluent(claim(c17,"Ancestry queries determine type. Three options given: walk parent chain, materialized path/closure table, cached archetype tag. Spec says start simple.",input(i6))).
fluent(claim(c16,"Inheritance tree: $root -> $room, $exit, $motile -> $mob -> $human -> $pc/$npc, $immobile, $wieldable, $skill -> 19 children",input(i5))).
fluent(claim(c15,"Integration notes confirm: object graph + verb dispatch + PubSub form the spine. Verification sequence: create room, create player, place in room, dispatch look.",input(i13))).
fluent(claim(c14,"Stack: Elixir 1.16+/OTP 26+, Phoenix 1.7+, PostgreSQL via Ecto, Bandit HTTP. No frontend build pipeline.",input(i1))).
fluent(claim(c13,"Umbrella: line_shared (library) < line_core (MOO core) < line_web (Phoenix). line_world and line_ml depend on line_core+line_shared.",input(i1))).
fluent(claim(c12,"4 core stats: Faction Rep (per-faction), Social Clout (Signal upload driven), Money (Dirham+Yuan), Signal (upload+download bandwidth).",input(i12))).
fluent(claim(c11,"3 health bars: HP (Iron-scaled), Fatigue (Vigor-scaled), Stress (flat cap, rate-scaled by behavior/environment).",input(i11))).
fluent(claim(c10,"19 skills as objects descended from $skill. Total = stat_a + stat_b. Combat skills have separate attack_speed_stat (Vigor melee, Rigor ranged).",input(i10))).
fluent(claim(c9,"8 chargen attributes: opposition pairs Wire-Shade, Grit-Face, Wit-Iron, plus independent Rigor and Vigor. Set at chargen.",input(i9))).
fluent(claim(c8,"Exits are full objects. Doors are multi-contained (in both rooms). Direction on containment edge, lock state on exit object.",input(i8))).
fluent(claim(c7,"Movement protocol: accept verb -> loop check -> remove old containment -> add new containment -> exitfunc -> enterfunc.",input(i8))).
fluent(claim(c6,"Verb search order: player -> room -> dobj -> iobj, each walking parent chain. Argument specifiers: dobj/prep/iobj with none/any/this values.",input(i7))).
fluent(claim(c5,"Inheritance (parent_id) and containment (relationship) are two completely independent hierarchies. Never conflate them.",input(i6))).
fluent(claim(c4,"Dispatcher owns ALL side effects. Persistence and notification happen there and nowhere else. Ecto.Multi atomic transactions.",input(i4))).
fluent(claim(c3,"Verbs are objects attached to other objects. Verb execute/2 is pure. Returns events only.",input(i4))).
fluent(claim(c2,"Everything is an object in one table. Type from ancestry, not enum. UUIDs everywhere. Properties are JSONB-wrapped. Soft deletes only.",input(i4))).
fluent(claim(c1,"The dispatch spine is: Parser -> Dispatcher -> Verb (pure, returns events) -> Dispatcher applies events (Ecto.Multi) + broadcasts (PubSub)",input(i4))).
fluent(input(i15,tool_result,"00000001")).
fluent(input(i14,user_message,"00000000")).
fluent(input(i13,file_content,'5f01e416')).
fluent(input(i12,file_content,a1b3f269)).
fluent(input(i11,file_content,f1ba2d51)).
fluent(input(i10,file_content,'33f63926')).
fluent(input(i9,file_content,'23fa545f')).
fluent(input(i8,file_content,'8f13352e')).
fluent(input(i7,file_content,'9eff081c')).
fluent(input(i6,file_content,e0ad1a25)).
fluent(input(i5,file_content,'24cf2247')).
fluent(input(i4,file_content,'2d78fa26')).
fluent(input(i2,file_content,ed6d348e)).
fluent(input(i1,file_content,'88445ba3')).
fluent(phase(1)).
