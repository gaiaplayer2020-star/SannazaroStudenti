# Sannazzaro — Portale studenti

Prima bozza del portale studenti: avvisi, orario e materiali didattici. I contenuti visibili nella demo sono esempi e non sono comunicazioni ufficiali.

## Supabase

Lo schema iniziale è in `supabase-schema.sql`. Crea i profili, gli avvisi, le lezioni e i materiali, con Row Level Security attiva.

1. Crea un progetto Supabase e applica la migrazione dal SQL Editor o con Supabase CLI.
2. Dopo la registrazione, un amministratore deve assegnare `class_name` e `role` ai profili. Non usare i metadati di registrazione per assegnare classi o privilegi.
3. Configura l'accesso frontend usando solo la chiave `anon`/publishable. Non inserire mai la `service_role` nel browser.
4. Aggiungi il flusso di login e collega le query Supabase al frontend prima della pubblicazione.

La pagina attuale è una demo grafica: login, dati reali e caricamento di file non sono ancora collegati al progetto Supabase.
