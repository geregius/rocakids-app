// Service worker de Firebase Cloud Messaging (2026-09-02, notificaciones
// push) — recibe notificaciones cuando la pestaña de RocaKids está en
// segundo plano o cerrada. Mismos valores exactos de configuración que
// `lib/firebase_options.dart` (bloque `web`) — si ese archivo cambia
// (ej. se regenera con FlutterFire CLI), actualizar también acá.
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDGxqYiE70nwQkT4Zv2mv1t08Kc7nrfSgc',
  appId: '1:480177772801:web:b41567c5ee976a26d96300',
  messagingSenderId: '480177772801',
  projectId: 'rocakidsarmenia-7935b',
  authDomain: 'rocakidsarmenia-7935b.firebaseapp.com',
  storageBucket: 'rocakidsarmenia-7935b.firebasestorage.app',
});

firebase.messaging();
