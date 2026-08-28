# tAIdy (EconomyApp) - Guida Architetturale e Documentazione Tecnica

## Introduzione e Obiettivi del Progetto
tAIdy (conosciuto anche come EconomyApp) è un'applicazione modulare e scalabile per la gestione delle finanze personali. Il progetto nasce per aiutare gli utenti a tracciare, analizzare e comprendere le proprie abitudini di spesa attraverso un approccio strutturato e intuitivo.

A differenza di molti strumenti finanziari tradizionali, spesso appesantiti da funzionalità eccessive e interfacce complesse, abbiamo progettato tAIdy privilegiando la chiarezza, la modularità e la trasparenza. Ogni componente del sistema è stato sviluppato per essere facilmente comprensibile, estensibile e adattabile. Questo approccio rende l'applicazione uno strumento pratico per l'utente finale e, allo stesso tempo, un'eccellente piattaforma di studio per gli sviluppatori che desiderano esplorare un'architettura software pulita in un contesto reale.

A livello concettuale, il sistema modella il comportamento finanziario attraverso transazioni strutturate, ciascuna arricchita da metadati fondamentali come categoria, marca temporale (timestamp) e importo. Questi dati grezzi vengono poi processati per generare insight aggregati e trend storici.

## Architettura e Funzionamento
L'architettura di tAIdy si basa sul principio della separazione delle responsabilità (Separation of Concerns), implementata e orchestrata attraverso Riverpod. Questo design ci assicura che ogni modulo del sistema abbia uno scopo specifico, evitando pericolosi accoppiamenti tra l'interfaccia utente e le regole di business.

Il flusso dell'applicazione si articola su tre layer principali:

- **Layer di Presentazione (UI)**: Gestisce esclusivamente l'interazione con l'utente e il rendering dei dati. Non contiene logica di calcolo; si limita ad "ascoltare" lo stato fornito dai servizi Riverpod e ad aggiornarsi reattivamente.
- **Layer Logico**: Rappresenta il vero motore dell'applicazione. Al suo interno vengono processate le transazioni, eseguite le trasformazioni dei dati e gestiti i flussi di estrazione del testo tramite Intelligenza Artificiale (OCR). Questo strato è completamente indipendente dalla UI, risultando facilmente testabile.
- **Layer Dati**: Si occupa della persistenza e del recupero delle informazioni. Abbiamo implementato una soluzione ibrida:
  - **Hive (NoSQL)**: Garantisce l'archiviazione locale (crittografata tramite un sistema che chiamiamo eVault) e permette all'applicazione di funzionare in modo estremamente rapido, anche in assenza di connessione.
  - **Supabase**: Gestisce la sincronizzazione in cloud, fungendo da database remoto per il backup e l'accessibilità multi-dispositivo.
- **Layer AI e Machine Learning**: Un modulo dedicato all'elaborazione avanzata dei dati di input (come le ricevute). Supporta sia modelli di linguaggio in esecuzione locale (`llama.cpp`) per la massima privacy, sia chiamate ad API remote (es. Gemini) per alleggerire il carico computazionale.

Il flusso dei dati standard segue questa pipeline: `Input dell'utente -> Logica di Elaborazione -> Archiviazione Dati -> Aggregazione e Statistiche -> Output sulla UI`.

Per un'analisi approfondita dei singoli componenti, della gestione crittografica, del recupero da corruzione schema e dei record delle decisioni architetturali (ADR), consulta la [Documentazione Architetturale Dettagliata](docs/architecture.md).

## Prerequisiti e Installazione
Per compilare ed eseguire tAIdy, è necessario disporre di un ambiente di sviluppo Flutter configurato correttamente. Di seguito i requisiti software fondamentali:

- **Flutter SDK** (versione 3.10.4 o superiore): Il framework di base per la compilazione multipiattaforma.
- **Dart SDK**: Installato automaticamente con Flutter; necessario per l'esecuzione della logica applicativa.
- **Git**: Indispensabile per il versionamento del codice e per clonare il repository.

### Passaggi per l'Installazione

1. **Clonazione del repository**
   ```bash
   git clone https://github.com/TheZen46/EconomyApp.git
   cd EconomyApp
   ```
   *Spiegazione*: Questo comando scarica l'intero codice sorgente del progetto sulla tua macchina locale e ti sposta all'interno della directory di lavoro.

2. **Installazione delle dipendenze**
   ```bash
   flutter pub get
   ```
   *Spiegazione*: Attraverso questo comando, il gestore di pacchetti di Dart legge il file `pubspec.yaml` e scarica tutte le librerie esterne necessarie (come Riverpod, Hive, e i plugin per l'Intelligenza Artificiale). È un passaggio obbligatorio prima di tentare qualsiasi compilazione, altrimenti il compilatore non troverà i moduli referenziati nel codice.

3. **Configurazione dell'ambiente (File .env)**
   Per abilitare i servizi cloud e le API AI esterne, è necessario configurare le variabili d'ambiente. Se il progetto prevede un file `.env.example`, copialo e rinominalo in `.env`, inserendo al suo interno le chiavi API richieste (ad esempio, le credenziali di Supabase).

4. **Avvio dell'applicazione**
   ```bash
   flutter run
   ```
   *Spiegazione*: Questo comando compila l'applicazione per la piattaforma target disponibile (es. un emulatore Android/iOS o un dispositivo web). Se sono connessi più dispositivi, Flutter ti chiederà di selezionarne uno. Puoi forzare l'esecuzione su un dispositivo specifico usando il flag `-d`, ad esempio `flutter run -d chrome`.

## Guida all'Utilizzo (Usage)
Sebbene il progetto sia in fase di sviluppo, il flusso di lavoro principale è già delineato. L'obiettivo dell'applicazione è trasformare dati finanziari frammentati in informazioni strutturate.

Quando un utente effettua una spesa, registra una transazione (manualmente o scansionando uno scontrino tramite AI). Il sistema processa questa entità aggiornando i totali e distribuendo la spesa nelle categorie pertinenti.

Di seguito, un esempio concettuale di come gestiamo il salvataggio di una transazione all'interno del nostro Layer Logico, sfruttando Riverpod e Hive:

```dart
// Esempio concettuale di gestione delle transazioni nel Layer Logico
Future<void> addTransaction(WidgetRef ref, double amount, String category) async {
  // 1. Inizializzazione del modello dati strutturato
  final newTransaction = Transaction(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    amount: amount, // Valore negativo per le uscite (es. -20.0)
    category: category,
    date: DateTime.now(),
  );

  // 2. Interazione con il Layer Dati
  // Utilizziamo ref.read per accedere al servizio di storage in modo disaccoppiato
  final storageService = ref.read(storageServiceProvider);
  await storageService.save(newTransaction);

  // 3. Notifica di aggiornamento
  // L'architettura Riverpod rileverà la modifica nel database locale
  // e notificherà automaticamente la UI per aggiornare grafici e saldi.
}
```
*Spiegazione del codice*: In questo frammento, generiamo un identificatore univoco basato sul timestamp corrente per garantire che nessuna transazione venga sovrascritta accidentalmente. Successivamente, istanziamo l'oggetto `Transaction` e lo passiamo al nostro servizio asincrono `storageService`. Grazie all'approccio reattivo di Riverpod, non abbiamo bisogno di scrivere codice aggiuntivo per forzare il refresh della schermata: i widget che osservano lo stato si aggiorneranno da soli non appena il salvataggio sarà completato.

## Configurazione Avanzata e Moduli Specifici
tAIdy include moduli avanzati per gestire casistiche complesse legate alla privacy e alle performance:

- **Isolamento della Privacy (Data Privacy Isolation Mode)**: In risposta alle esigenze di confidenzialità sui dati finanziari, stiamo implementando un interruttore (toggle) di sicurezza locale. Quando attivato, il sistema blocca esplicitamente qualsiasi chiamata di rete verso Supabase, confinando le operazioni di lettura e scrittura esclusivamente al database locale Hive.
- **Graceful Degradation per l'Intelligenza Artificiale**: Il modulo OCR per l'analisi degli scontrini si affida tipicamente a `llama.cpp` per operare localmente. Poiché l'inferenza locale è intensiva sia per la memoria che per la batteria, il sistema prevede una logica di "degradazione controllata". Se il dispositivo segnala un livello di batteria critico o risorse di sistema insufficienti, l'elaborazione viene automaticamente instradata verso API remote (come Groq o Google Cloud), prevenendo il blocco dell'applicazione e preservando l'autonomia dello smartphone.

## Risoluzione dei Problemi Frequenti (Troubleshooting)
Durante l'installazione o lo sviluppo, potrebbero verificarsi alcuni intoppi. Ecco i problemi più comuni e le relative soluzioni:

- **Problema: Errore "Target of URI doesn't exist" o classi non trovate.**
  - *Causa*: I pacchetti Dart necessari non sono presenti nel sistema, o ci sono conflitti di versione nella cache.
  - *Soluzione*: Pulisci la cache del progetto eseguendo `flutter clean`, dopodiché esegui nuovamente `flutter pub get` per forzare un'installazione pulita delle dipendenze.

- **Problema: Schermata bianca o crash immediato all'avvio dell'app.**
  - *Causa*: Il database locale Hive non è stato inizializzato prima del rendering dell'interfaccia utente.
  - *Soluzione*: Assicurati che nel file `main.dart`, la funzione asincrona di setup (es. `await Hive.initFlutter();`) sia chiamata prima di `runApp()`, e che il metodo `main` sia contrassegnato con `WidgetsFlutterBinding.ensureInitialized();`.

- **Problema: L'applicazione si chiude improvvisamente (OOM - Out of Memory) durante l'uso dell'OCR AI.**
  - *Causa*: Il modello Llama caricato in locale per l'elaborazione degli scontrini ha saturato la memoria RAM disponibile sul dispositivo mobile.
  - *Soluzione*: Verifica i log di debug per confermare l'errore di memoria. Per ovviare temporaneamente al problema su dispositivi datati, attiva la modalità di fallback in cloud per delegare il calcolo a un server esterno.

- **Problema: Nessuna sincronizzazione con il cloud / Errori di autenticazione.**
  - *Causa*: Le variabili d'ambiente per Supabase non sono state caricate correttamente.
  - *Soluzione*: Controlla che il file `.env` sia presente, formattato correttamente (senza spazi imprevisti) e che le variabili (es. `SUPABASE_URL`) corrispondano esattamente a quelle fornite nella dashboard del tuo progetto Supabase.
