// Shared Firebase initialization for Vaahana web.
import { initializeApp } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-app.js";
import {
  getAuth,
  setPersistence,
  browserLocalPersistence,
  onAuthStateChanged,
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  signOut,
  sendEmailVerification,
  updateProfile,
  reload,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-auth.js";
import {
  getFirestore,
  doc,
  getDoc,
  setDoc,
  updateDoc,
  collection,
  addDoc,
  query,
  where,
  orderBy,
  limit,
  onSnapshot,
  serverTimestamp,
  Timestamp,
  runTransaction,
  getDocs,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import {
  getFunctions,
  httpsCallable,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-functions.js";

const firebaseConfig = {
  apiKey:            "AIzaSyAqHRI6HHkxbyr3Cb-TZue0r7JvKDpuTxk",
  authDomain:        "vaahana-fb9b8.firebaseapp.com",
  projectId:         "vaahana-fb9b8",
  storageBucket:     "vaahana-fb9b8.firebasestorage.app",
  messagingSenderId: "803618464965",
  appId:             "1:803618464965:web:d26b506573186f20893cac",
};

export const app  = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db   = getFirestore(app);
export const fn   = getFunctions(app);

// Keep the user signed in across reloads.
setPersistence(auth, browserLocalPersistence).catch(() => {});

export {
  onAuthStateChanged,
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  signOut,
  sendEmailVerification,
  updateProfile,
  reload,
  doc, getDoc, setDoc, updateDoc,
  collection, addDoc, query, where, orderBy, limit,
  onSnapshot, serverTimestamp, Timestamp, runTransaction, getDocs,
  httpsCallable,
};
