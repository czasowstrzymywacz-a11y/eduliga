# Wersje i publikacja

- Numer wydania jest w `version.json`. Ten sam numer musi być widoczny w nagłówku strony i w metadanych `index.html`.
- Numer obecnego wydania odczytaj z version.json. Przy każdej kolejnej opublikowanej aktualizacji uruchom `./Update-Version.ps1` bez argumentów dokładnie raz, po zakończeniu zmian. Skrypt zwiększa drugi człon numeru wydania o jeden.
- Każda publikowana wersja musi mieć nowy wpis w historii zmian w `index.html`, z tym samym numerem co `version.json`. Najnowszy wpis oznacz jako „teraz” i usuń to oznaczenie ze starszego wpisu.
- Razem z plikami głównymi publikuj również `liga-angielska.js`, `liga-angielska.css` oraz `liga-social.js` i `liga-rankings.js`. Migracje bazy wdrażaj do istniejącego projektu Supabase przed publikacją funkcji, które z nich korzystają.
- Nie zwiększaj wersji przy samej analizie, zmianach roboczych ani ponowieniu nieudanego wysłania tego samego wydania. Przy świadomym ustawieniu numeru użyj parametru `-Version`.
- Do repozytorium publikacyjnego przenieś razem `index.html`, `ortoliga-core.js`, `ortoliga.js`, `ortoliga.css`, `version.json`, `Update-Version.ps1`, `URUCHOMIENIE-SYNC.md`, `supabase/config.toml`, `supabase/functions` i `supabase/migrations` oraz ten plik. Zmiany funkcji Edge wdrażaj do projektu Supabase zgodnie z dokumentacją. Jeśli istnieje `.publish-stage`, to obecny klon służący do publikacji.
- Użytkownik upoważnił do publikowania gotowych aktualizacji w istniejącym repozytorium GitHub Pages.
- Nazwę aplikacji zmień wyłącznie po zatwierdzeniu konkretnej nazwy przez użytkownika. Propozycje nazw i usprawnień nie stanowią zgody na ich wdrożenie.


