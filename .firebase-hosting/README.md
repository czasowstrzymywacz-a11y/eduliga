# Przygotowanie adresu eduliga.web.app

Status: wersja 0.66 opublikowana pod https://eduliga.web.app/. Projekt i witryna Hosting: `eduliga`, plan Spark. Użytkownik osobno zatwierdził uprawnienia oficjalnego Firebase CLI. Supabase Auth ma nowy Site URL i dokładny Redirect URL; stare powroty pozostają dozwolone.
Wersję zwiększono dokładnie raz do 0.66. Nie przenoszono bazy danych ani kont do Firebase.

1. Włączyć dostęp do przeglądarki w Work i otworzyć Firebase Console na koncie właściciela.
2. Sprawdzić, czy identyfikator witryny Hosting `eduliga` jest dostępny. Brak strony pod adresem nie potwierdza dostępności nazwy.
3. Wybrać lub utworzyć projekt Firebase w bezpłatnym planie Spark. Zaakceptowanie ewentualnych umów wykonuje właściciel. Nie włączać płatnego planu ani analityki bez decyzji użytkownika.
4. Utworzyć Hosting site `eduliga` w wybranym projekcie. Zapisać rzeczywisty project ID; nie zakładać, że jest taki sam jak site ID.
5. Dodać w istniejącym Supabase Auth nowy adres i adresy powrotu odzyskiwania hasła / potwierdzania konta. Baza i konta pozostają w Supabase.
6. Przygotować przeniesienie lokalnych wyników gości. Nowa domena nie odczyta localStorage poprzedniej. Sesja zalogowanego konta także wymaga ponownego logowania; potwierdzić zapis wyników w chmurze przed przejściem.
7. Uruchomić Prepare-Hosting.ps1. Publiczna paczka jest ograniczona jawną listą plików aplikacji; nie zawiera migracji, funkcji, testów, repozytorium ani konfiguracji administracyjnej.
8. Po autoryzacji Firebase CLI wdrożyć tylko Hosting z tego folderu, wskazując rzeczywisty project ID. Konfiguracja site wymaga wcześniejszego utworzenia witryny.
9. Potwierdzić działanie nowego adresu i logowania. Dopiero potem ustawić nowy adres główny i przekierowania, z nowym wpisem historii i pojedynczą aktualizacją numeru wersji zgodnie z AGENTS.md.
10. Przygotować automatyczne aktualizacje wyłącznie po nadaniu minimalnych uprawnień do docelowego hostingu. Nie zapisywać tokenów ani kluczy w repozytorium.

Dokumentacja: https://firebase.google.com/docs/hosting/quickstart

## Narzędzie publikacji

Oficjalny `firebase-tools` 15.34.0 zainstalowano lokalnie w `tools/` przez rejestr npm. Windows standalone nie uruchomił się poprawnie; publikację wykonuj przez `node tools/node_modules/firebase-tools/lib/bin/firebase.js`. Używaj `NODE_USE_SYSTEM_CA=1`, bez wyłączania weryfikacji TLS. Po zalogowaniu można uruchomić `./Deploy-Hosting.ps1`; wysyła tylko publiczną paczkę do projektu `eduliga`. Skrypt nie zwiększa wersji — numer i historia muszą być przygotowane wcześniej zgodnie z AGENTS.md.

Po potwierdzeniu nowej strony oba wcześniejsze adresy mają nadal działać. Nie wprowadzaj bezwarunkowego przekierowania użytkowników z wynikami lokalnymi lub niezapisanymi zmianami. Najpierw zapewnij im zachowanie dostępu do dotychczasowych wyników i możliwość zapisania wyników na koncie. Tokenów sesji nie przenoś pomiędzy domenami. Linki odzyskiwania hasła wysłane na stary adres również muszą pozostać obsługiwane.
