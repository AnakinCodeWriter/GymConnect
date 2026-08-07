// Firestore security-rules tests for GymConnect (Phase 10).
//
// Runs against the local Firestore EMULATOR only (no live credentials, no
// network project): `npm --prefix test_rules test` from the repo root
// wraps this in `firebase emulators:exec --project demo-gymconnect`.
// The demo- project prefix guarantees an offline-only project.
//
// Fixtures: alice + bob belong to gym-a, carol to gym-b; profiles are
// seeded with rules disabled (the app guarantees a profile exists before
// any leaderboard access - ProfileGate).

import { readFileSync } from 'node:fs';
import { after, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
  setLogLevel,
  updateDoc,
} from 'firebase/firestore';

setLogLevel('error'); // silence expected permission-denied noise

const testEnv = await initializeTestEnvironment({
  projectId: 'demo-gymconnect',
  firestore: {
    rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
  },
});

after(async () => {
  await testEnv.cleanup();
});

const profile = (name, gymId) => ({
  displayName: name,
  gymId,
  createdAt: new Date(),
  isAnonymous: false,
  experienceLevel: 'Beginner',
  fitnessGoal: 'Build Muscle',
  goalExercise: '',
  goalTargetWeight: 0,
  personalRecords: {},
  weightUnit: 'kg',
});

const workout = () => ({
  date: new Date(),
  exercises: [{ name: 'Bench Press', sets: [{ weight: 60, reps: 5 }] }],
});

const db = (uid) => testEnv.authenticatedContext(uid).firestore();
const anon = () => testEnv.unauthenticatedContext().firestore();

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, 'users/alice'), profile('Alice', 'gym-a'));
    await setDoc(doc(f, 'users/bob'), profile('Bob', 'gym-a'));
    await setDoc(doc(f, 'users/carol'), profile('Carol', 'gym-b'));
    await setDoc(doc(f, 'users/bob/workouts/w1'), workout());
    await setDoc(doc(f, 'users/bob/templates/t1'), {
      name: 'Push Day',
      exercises: [],
    });
    await setDoc(doc(f, 'gyms/gym-a/leaderboard/bob'), {
      displayName: 'Bob',
      isAnonymous: false,
      bestLifts: { 'Bench Press': 100 },
    });
    await setDoc(doc(f, 'gyms/gym-b/leaderboard/carol'), {
      displayName: 'Carol',
      isAnonymous: false,
      bestLifts: { Squat: 120 },
    });
  });
});

describe('profiles', () => {
  it('unauthenticated users cannot read or write profiles', async () => {
    await assertFails(getDoc(doc(anon(), 'users/alice')));
    await assertFails(
      setDoc(doc(anon(), 'users/alice'), profile('X', 'gym-a')),
    );
  });

  it('a user can create their own valid profile', async () => {
    await assertSucceeds(
      setDoc(doc(db('dave'), 'users/dave'), profile('Dave', 'gym-a')),
    );
  });

  it('a user can read and update their own profile', async () => {
    await assertSucceeds(getDoc(doc(db('alice'), 'users/alice')));
    await assertSucceeds(
      updateDoc(doc(db('alice'), 'users/alice'), {
        displayName: 'Alice R',
        experienceLevel: 'Intermediate',
        fitnessGoal: 'Build Muscle',
        weightUnit: 'lbs',
      }),
    );
  });

  it("a user cannot read another user's profile", async () => {
    await assertFails(getDoc(doc(db('alice'), 'users/bob')));
  });

  it("a user cannot update another user's profile", async () => {
    await assertFails(
      updateDoc(doc(db('alice'), 'users/bob'), { displayName: 'Hacked' }),
    );
  });

  it('malformed profile writes are denied', async () => {
    // displayName must be a string
    await assertFails(
      setDoc(doc(db('dave'), 'users/dave'), {
        ...profile('Dave', 'gym-a'),
        displayName: 42,
      }),
    );
    // gymId is required
    const noGym = profile('Dave', 'gym-a');
    delete noGym.gymId;
    await assertFails(setDoc(doc(db('dave'), 'users/dave'), noGym));
    // createdAt must be a timestamp
    await assertFails(
      setDoc(doc(db('dave'), 'users/dave'), {
        ...profile('Dave', 'gym-a'),
        createdAt: 'today',
      }),
    );
    // optional field with a wrong type
    await assertFails(
      setDoc(doc(db('dave'), 'users/dave'), {
        ...profile('Dave', 'gym-a'),
        personalRecords: 'none',
      }),
    );
  });

  it('profiles cannot be deleted from the client', async () => {
    await assertFails(deleteDoc(doc(db('alice'), 'users/alice')));
  });
});

describe('workouts', () => {
  it('a user can create, read, update and delete their own workout', async () => {
    const ref = doc(db('alice'), 'users/alice/workouts/w1');
    await assertSucceeds(setDoc(ref, workout()));
    await assertSucceeds(getDoc(ref));
    await assertSucceeds(updateDoc(ref, { name: 'Push Day' }));
    await assertSucceeds(deleteDoc(ref));
  });

  it("a user cannot read another user's workouts (get and list)", async () => {
    await assertFails(getDoc(doc(db('alice'), 'users/bob/workouts/w1')));
    await assertFails(getDocs(collection(db('alice'), 'users/bob/workouts')));
  });

  it("a user cannot write or delete another user's workout", async () => {
    await assertFails(
      setDoc(doc(db('alice'), 'users/bob/workouts/w2'), workout()),
    );
    await assertFails(deleteDoc(doc(db('alice'), 'users/bob/workouts/w1')));
  });

  it('unauthenticated workout access is denied', async () => {
    await assertFails(getDocs(collection(anon(), 'users/alice/workouts')));
    await assertFails(
      setDoc(doc(anon(), 'users/alice/workouts/w9'), workout()),
    );
  });

  it('demo-tagged workouts are allowed on the owner, with correct types',
    async () => {
      await assertSucceeds(
        setDoc(doc(db('alice'), 'users/alice/workouts/demo-1'), {
          ...workout(),
          isDemo: true,
          demoScenario: 'progressing',
          demoBatchId: 'progressing',
          demoGeneratedAt: '2026-07-05T10:00:00.000Z',
        }),
      );
    });

  it('demo fields with wrong types are denied', async () => {
    await assertFails(
      setDoc(doc(db('alice'), 'users/alice/workouts/demo-2'), {
        ...workout(),
        isDemo: 'true', // must be bool
      }),
    );
    await assertFails(
      setDoc(doc(db('alice'), 'users/alice/workouts/demo-3'), {
        ...workout(),
        isDemo: true,
        demoBatchId: 7, // must be string
      }),
    );
  });

  it("demo fields grant no access to another user's data", async () => {
    await assertFails(
      setDoc(doc(db('alice'), 'users/bob/workouts/demo-1'), {
        ...workout(),
        isDemo: true,
      }),
    );
  });

  it('workout validation: date/exercises required, feelRating 1-5', async () => {
    await assertFails(
      setDoc(doc(db('alice'), 'users/alice/workouts/bad-1'), {
        exercises: [],
      }), // no date
    );
    await assertFails(
      setDoc(doc(db('alice'), 'users/alice/workouts/bad-2'), {
        date: new Date(),
        exercises: 'none', // must be a list
      }),
    );
    await assertFails(
      setDoc(doc(db('alice'), 'users/alice/workouts/bad-3'), {
        ...workout(),
        feelRating: 7,
      }),
    );
    await assertSucceeds(
      setDoc(doc(db('alice'), 'users/alice/workouts/ok-1'), {
        ...workout(),
        feelRating: 3,
        name: 'Evening session',
      }),
    );
  });
});

describe('templates', () => {
  it('a user can create, read, update and delete their own template', async () => {
    const ref = doc(db('alice'), 'users/alice/templates/t1');
    await assertSucceeds(setDoc(ref, { name: 'Legs', exercises: [] }));
    await assertSucceeds(getDoc(ref));
    await assertSucceeds(updateDoc(ref, { name: 'Leg Day' }));
    await assertSucceeds(deleteDoc(ref));
  });

  it("a user cannot access another user's templates", async () => {
    await assertFails(getDoc(doc(db('alice'), 'users/bob/templates/t1')));
    await assertFails(
      setDoc(doc(db('alice'), 'users/bob/templates/t2'), {
        name: 'X',
        exercises: [],
      }),
    );
  });

  it('unauthenticated template access is denied', async () => {
    await assertFails(getDocs(collection(anon(), 'users/alice/templates')));
  });

  it('malformed templates are denied', async () => {
    await assertFails(
      setDoc(doc(db('alice'), 'users/alice/templates/bad'), {
        exercises: [],
      }), // no name
    );
  });
});

describe('leaderboard', () => {
  const entry = (name, anonFlag) => ({
    displayName: name,
    isAnonymous: anonFlag,
    bestLifts: { 'Bench Press': 110 },
  });

  it('a member can write their own entry for their own gym', async () => {
    await assertSucceeds(
      setDoc(doc(db('alice'), 'gyms/gym-a/leaderboard/alice'),
        entry('Alice', false)),
    );
  });

  it("a member cannot write another user's entry", async () => {
    await assertFails(
      setDoc(doc(db('alice'), 'gyms/gym-a/leaderboard/bob'),
        entry('Bob', false)),
    );
  });

  it("a member cannot write their entry under a gym that is not their "
    + "profile's gym", async () => {
    await assertFails(
      setDoc(doc(db('alice'), 'gyms/gym-b/leaderboard/alice'),
        entry('Alice', false)),
    );
  });

  it('members can read their own gym; other gyms are denied', async () => {
    await assertSucceeds(
      getDocs(collection(db('alice'), 'gyms/gym-a/leaderboard')),
    );
    await assertSucceeds(
      getDoc(doc(db('alice'), 'gyms/gym-a/leaderboard/bob')),
    );
    await assertFails(
      getDocs(collection(db('alice'), 'gyms/gym-b/leaderboard')),
    );
    await assertFails(
      getDoc(doc(db('alice'), 'gyms/gym-b/leaderboard/carol')),
    );
  });

  it('a user with no profile cannot read any leaderboard', async () => {
    await assertFails(
      getDocs(collection(db('ghost'), 'gyms/gym-a/leaderboard')),
    );
  });

  it('an anonymous entry containing a real display name is denied', async () => {
    await assertFails(
      setDoc(doc(db('alice'), 'gyms/gym-a/leaderboard/alice'),
        entry('Alice', true)),
    );
  });

  it('an anonymous entry with the safe display value is allowed', async () => {
    await assertSucceeds(
      setDoc(doc(db('alice'), 'gyms/gym-a/leaderboard/alice'),
        entry('Anonymous', true)),
    );
  });

  it('toggling anonymity in both directions produces compliant shapes '
    + '(the merge writes LeaderboardService performs)', async () => {
    const ref = doc(db('alice'), 'gyms/gym-a/leaderboard/alice');
    await assertSucceeds(setDoc(ref, entry('Alice', false)));
    // ON: service writes safe value + flag
    await assertSucceeds(
      setDoc(ref, { isAnonymous: true, displayName: 'Anonymous' },
        { merge: true }),
    );
    // OFF: service restores the profile name
    await assertSucceeds(
      setDoc(ref, { isAnonymous: false, displayName: 'Alice' },
        { merge: true }),
    );
    // ON without sanitising the name (the pre-Phase-10 write shape) fails
    await assertFails(
      setDoc(ref, { isAnonymous: true }, { merge: true }),
    );
  });

  it('malformed entries are denied (types and closed field set)', async () => {
    await assertFails(
      setDoc(doc(db('alice'), 'gyms/gym-a/leaderboard/alice'), {
        displayName: 'Alice',
        isAnonymous: 'no', // must be bool
      }),
    );
    await assertFails(
      setDoc(doc(db('alice'), 'gyms/gym-a/leaderboard/alice'), {
        displayName: 'Alice',
        isAnonymous: false,
        bestLifts: 'strong', // must be a map
      }),
    );
    await assertFails(
      setDoc(doc(db('alice'), 'gyms/gym-a/leaderboard/alice'), {
        ...entry('Alice', false),
        admin: true, // unexpected field - closed set
      }),
    );
  });

  it('unauthenticated leaderboard access is denied', async () => {
    await assertFails(getDocs(collection(anon(), 'gyms/gym-a/leaderboard')));
    await assertFails(
      setDoc(doc(anon(), 'gyms/gym-a/leaderboard/alice'),
        entry('Alice', false)),
    );
  });

  it('leaderboard entries cannot be deleted from the client', async () => {
    await assertFails(
      deleteDoc(doc(db('bob'), 'gyms/gym-a/leaderboard/bob')),
    );
  });
});

describe('deny by default', () => {
  it('unknown top-level collections are denied even when authenticated',
    async () => {
      await assertFails(getDoc(doc(db('alice'), 'admin/config')));
      await assertFails(
        setDoc(doc(db('alice'), 'admin/config'), { root: true }),
      );
    });

  it('unknown nested paths under a user document are denied', async () => {
    await assertFails(
      setDoc(doc(db('alice'), 'users/alice/secrets/s1'), { token: 'x' }),
    );
    await assertFails(
      getDoc(doc(db('alice'), 'users/alice/secrets/s1')),
    );
  });

  it('gym documents themselves are not readable or writable', async () => {
    await assertFails(getDoc(doc(db('alice'), 'gyms/gym-a')));
    await assertFails(setDoc(doc(db('alice'), 'gyms/gym-a'), { name: 'x' }));
  });
});
