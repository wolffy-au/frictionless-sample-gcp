import { initializeApp } from "https://www.gstatic.com/firebasejs/13.4.0/firebase-app.js";
import {
  collection,
  connectFirestoreEmulator,
  doc,
  getDocs,
  getFirestore,
  orderBy,
  query,
  runTransaction,
} from "https://www.gstatic.com/firebasejs/13.4.0/firebase-firestore.js";

// Must match isSeed() in firestore.rules, which rejects any other write.
const SEED_ITEMS = [
  { Id: 1, Name: "Notebook", Category: "Stationery" },
  { Id: 2, Name: "Coffee mug", Category: "Kitchen" },
  { Id: 3, Name: "Backpack", Category: "Travel" },
];

const statusMessage = document.querySelector("#status");
const tableBody = document.querySelector("#items");

async function getDb() {
  // Firebase Hosting serves the project's web config at this reserved URL, so
  // no project-specific config is committed. The config is not a secret:
  // firestore.rules decides what a browser may do.
  const response = await fetch("/__/firebase/init.json");
  if (!response.ok) {
    throw new Error("Firebase config unavailable: serve this page from Firebase Hosting or the emulator.");
  }

  const db = getFirestore(initializeApp(await response.json()));
  if (["localhost", "127.0.0.1"].includes(location.hostname)) {
    connectFirestoreEmulator(db, "127.0.0.1", 8080);
  }
  return db;
}

async function seedItems(db) {
  // Browser transactions can only read documents by reference, not queries,
  // so check each seed document. If another visitor seeds concurrently, the
  // transaction retries and finds the documents already exist.
  await runTransaction(db, async (tx) => {
    const refs = SEED_ITEMS.map((item) => doc(db, "demoItems", String(item.Id)));
    const snapshots = await Promise.all(refs.map((ref) => tx.get(ref)));
    snapshots.forEach((snapshot, index) => {
      if (!snapshot.exists()) {
        tx.set(refs[index], SEED_ITEMS[index]);
      }
    });
  });
}

async function readItems(db) {
  const snapshot = await getDocs(query(collection(db, "demoItems"), orderBy("Id")));
  return snapshot.docs.map((d) => d.data());
}

async function loadItems() {
  try {
    const db = await getDb();
    let items = await readItems(db);
    if (items.length === 0) {
      await seedItems(db);
      items = await readItems(db);
    }

    for (const item of items) {
      const row = document.createElement("tr");
      for (const value of [item.Id, item.Name, item.Category]) {
        const cell = document.createElement("td");
        cell.textContent = String(value);
        row.append(cell);
      }
      tableBody.append(row);
    }

    statusMessage.textContent = `${items.length} rows loaded from Cloud Firestore.`;
  } catch (error) {
    console.error("Unable to load demo items from Firestore.", error);
    statusMessage.textContent = "Unable to load demo items. Check the browser console for details.";
  }
}

async function loadVersion() {
  const versionLabel = document.querySelector("#version");

  try {
    const response = await fetch("/version.json", { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`Request failed (${response.status}).`);
    }

    const { version, builtAt } = await response.json();
    versionLabel.textContent = `${version} · ${new Date(builtAt).toLocaleString()}`;
    versionLabel.title = `Version ${version}, built ${builtAt}`;
  } catch {
    versionLabel.textContent = "development build";
  }
}

loadItems();
loadVersion();
