## overview

LayoutSwitcher urmărește intrările globale de la tastatură și corectează greșelile de aranjament atunci când o poate face în siguranță.

Exemplu:
• Tastezi "ghbdtn " cu aranjamentul englez activ.
• După spațiu, aplicația recunoaște că textul se citește ca rusă.
• Înlocuiește cuvântul tocmai tastat cu "привет " și comută la aranjamentul corespunzător.

Fluxul automat funcționează de obicei cuvânt cu cuvânt și poate uni o secvență sigură de 2-3 cuvinte în aranjamentul greșit, separate prin spații, într-o singură înlocuire. Nu rescrie automat o propoziție întreagă deja tastată. Pentru text mai lung, folosește Conversia textului selectat: selectezi textul exact, apeși scurtătura și aplicația înlocuiește acea selecție.

Direcții lingvistice acceptate:
• Engleză ⇄ Rusă
• Engleză ⇄ Ucraineană
• Engleză ⇄ Română
• ASCII român → română cu diacritice, când este activat

## first-setup

La prima lansare, deschide Setările din bara de meniu și parcurge cele trei verificări:

1. Acordă permisiunea de Accesibilitate. macOS o cere pentru monitorizarea globală a tastaturii și pentru trimiterea evenimentelor de înlocuire. Fără ea, LayoutSwitcher nu poate corecta text.
2. Activează sursele de intrare necesare în Setările de sistem → Tastatură → Surse de intrare. Ai nevoie de engleză plus cel puțin o limbă țintă: rusă, ucraineană sau română.
3. Asigură-te că aranjamentul țintă poate tasta caracterele așteptate. Diacriticele românești cer Romanian - Standard, nu doar un aranjament englez.

Indicatorul din bara de meniu afișează codul de limbă macOS curent: EN, RU, UK sau RO. În textele aplicației, ucraineana este descrisă ca UA/Ukrainian pentru a nu fi confundată cu engleza britanică; intern, macOS raportează tot codul "uk".

Dacă accesibilitatea este acordată dar aplicația se comportă de parcă nu ar fi, șterge LayoutSwitcher din Setările de sistem → Confidențialitate și securitate → Accesibilitate, adaugă-l din nou și repornește aplicația.

## automatic-correction

Fluxul automat este în mod deliberat restrâns:

1. Fiecare keyDown este adăugat într-un buffer de cuvânt din memorie.
2. Spațiul sau punctuația încheie cuvântul curent.
3. Enter și Tab închid cuvântul, dar nu declanșează o înlocuire automată, deoarece pot trimite mesajul sau muta focusul.
4. Detectorul evaluează cuvântul în engleză, rusă, ucraineană și română.
5. Dacă citirea într-un alt aranjament este clar mai bună, aplicația șterge cuvântul plus separatorul, comută aranjamentul și retastează cuvântul corectat plus același separator.
6. Buffer-ul de cuvânt se resetează. Cuvintele anterioare rămân în afara buffer-ului și nu sunt atinse.

Cuvintele cu cifre sunt sărite. De obicei sunt nume, versiuni, parole, modele sau texte tehnice mixte.

Tokenurile tehnice sunt sărite și ele: URL-uri, adrese e-mail, @handles, căi de fișiere și nume de pachete cu puncte sunt tratate ca text neconvertibil.

Câmpurile securizate sunt sărite complet. Când focusul este într-un câmp de parolă, fluxul încetează să mai proceseze tastele.

Buffer-ul se resetează și la schimbări de focus, clicuri de mouse, scurtături cu modificatori și alte interacțiuni care fac poziția textului nesigură.

## extending-corrections

LayoutSwitcher poate corecta nu doar un cuvânt, ci mai multe cuvinte consecutive dacă împreună formează o serie clară „în aranjament greșit".

Retastare secvențială (mereu activă):
Când tastezi două sau trei cuvinte la rând în aranjament greșit, separate prin spații unice, și fiecare este în mod sigur o comutare în sine, aplicația le îmbină într-o singură operație de ștergere-și-retastare, în loc să se declanșeze pentru fiecare cuvânt. Înlocuirea acoperă întreaga serie plus separatorul final.

Auto-extend recent ambiguous words (opțional):
Activabil în Preferences → Detection. Când un cuvânt mai lung declanșează o comutare, pipeline-ul se uită înapoi la cuvintele recent comise și include pe acelea care erau ambigue în sine dar aparțin clar aceleiași limbi ca declanșatorul.

Exemplu cu butonul activat:
• Tastezi "z nt,t " pe aranjamentul englez.
• "z" singur este prea scurt pentru o decizie sigură, deci se comite ca ambiguu.
• "nt,t" se citește clar ca rusescul „тебе" și declanșează comutarea.
• Auto-extend reevaluează "z" cu corecția single-char activată, vede corespondența cu „я" și îl include în înlocuire.
• Rezultat: „я тебе ".

Fără buton, doar cuvântul declanșator este retastat, iar "z" rămâne așa cum era.

Constrângeri pentru auto-extend:
• Până la patru cuvinte anterioare într-o fereastră de două secunde.
• Aceeași aplicație în focus — schimbarea aplicației oprește parcurgerea.
• Cuvintele trebuie separate doar prin spații obișnuite — Enter, Tab sau punctuația de sfârșit de propoziție opresc parcurgerea.
• Cuvintele deja comutate automat sunt ignorate.

Convert single-character words (opțional, buton separat):
Când este activ, detectorul live corectează și un cuvânt de o singură literă chiar în momentul fixării separatorului, fără să fie nevoie de un declanșator vecin. Util pentru „я", „a", „и", „o" și particule similare.

Soluție manuală:
Dacă vrei să corectezi o propoziție pe care pipeline-ul automat a ratat-o — de exemplu un paragraf mai vechi, sau unul care conține punctuație pe care detectorul o tratează ca limită — apasă scurtătura Convert last sentence. Aceasta se întoarce de la ultimul cuvânt până la limita anterioară de propoziție și convertește seria finală cu modul agresiv single-character.

## manual-actions

Scurtăturile implicite curente:

• Comutare manuală a ultimului cuvânt: ⌃⌥\\
• Retapare forțată a ultimului cuvânt: ⌃⌥⌘R
• Anulare a ultimei comutări automate: ⌥⌘Z
• Conversia textului selectat: ⌃⌥⌘L
• Pauză automatizare comutare: ⌃⌥⌘P

Comutarea manuală retastează ultimul cuvânt încheiat în aranjamentul opus. Utilă când detectorul a decis să păstreze cuvântul, dar tu îl voiai comuta. Fereastra de siguranță este de 3 secunde și se curăță când focusul trece la altă aplicație.

Retaparea forțată rulează din nou detectorul pe ultimul cuvânt încheiat și îl retastează dacă este detectat un alt aranjament. Spre deosebire de comutarea manuală, nu are fereastră de siguranță și poate fi folosită oricând pentru a corecta un cuvânt care a scăpat comutării automate.

Anularea ultimei comutări automate restaurează caracterele originale din ultima corecție automată. Fereastra este tot de 3 secunde și este blocată pe aceeași aplicație unde a avut loc corecția.

Conversia textului selectat este pentru corecții multi-cuvânt. Nu depinde de buffer-ul de cuvânt: selectezi un cuvânt, o propoziție sau un paragraf și aplicația înlocuiește exact selecția simplă.

Pauza oprește temporar comutarea automată pentru durata configurată. Acțiunile manuale continuă să funcționeze, iar indicatorul din bara de meniu arată pauza rămasă ca P<minutes>.

Filă Scurtături permite acum modificarea directă a combinațiilor. Dacă atribui o combinație deja folosită de o altă acțiune, vechea asociere este eliminată automat.

## selection-conversion

Conversia textului selectat este fluxul recomandat pentru multi-cuvânt.

Flux:
1. Selectează exact textul pe care vrei să-l repari.
2. Apasă ⌃⌥⌘L.
3. LayoutSwitcher citește textul simplu selectat.
4. Încearcă direcțiile lingvistice probabile și alege conversia cu cel mai puternic semnal de dicționar/n-gram.
5. Înlocuiește doar selecția curentă.

Calea principală folosește citire/scrierea Accessibility pentru textul selectat. Dacă aplicația focusată nu o suportă, LayoutSwitcher trece pe calea clipboard-ului: salvează conținutul curent al clipboard-ului, copiază selecția, convertește textul simplu copiat, îl lipește înapoi și restaurează conținutul original al clipboard-ului.

Această funcție nu păstrează intenționat formatarea îmbogățită. Lucrează cu text simplu.

Limita de lungime a selecției este configurabilă în Setări → General → Conversia textului selectat. Implicit: 5000 caractere. Minim: 100. Maxim: 20000. Limita superioară există ca o selecție uriașă accidentală să nu declanșeze o înlocuire lungă și disruptivă.

Conversia este sărită în câmpurile securizate, selecții goale, selecții peste limita configurată și cazuri în care nu există un candidat clar în aranjamentul opus.

## preferences

General:
• LayoutSwitcher pornește sau oprește fluxul automat.
• Dispoziția curentă arată ultima sursă de intrare macOS observată.
• Accesibilitatea arată dacă macOS are încredere în aplicație.
• Ultima acțiune arată ultima corecție, motivul omisiunii sau o eroare.
• Adăugarea automată a diacriticelor românești activează conversia ASCII românesc → diacritice.
• Nivelul de agresivitate al corecției controlează pragurile detectorului: Conservator, Echilibrat sau Agresiv.
• Durata pauzei controlează cât timp scurtătura de pauză oprește comutarea automată.
• Numărul maxim de caractere selectate setează limita pentru conversia manuală a selecției.
• Statisticile afișează auto-comutări, comutări manuale, cuvinte confirmate și caractere salvate pentru azi și total.

Aranjamente:
• Afișează sursa de intrare curentă și pe cele activate.
• Afișează perechile lingvistice detectate: Rusă ⇄ Engleză, Ucraineană ⇄ Engleză, Română ⇄ Engleză.

Scurtături:
• Afișează combinațiile implicite curente pentru acțiuni manuale.

Excluderi:
• Permite adăugarea aplicațiilor în care retaparea automată nu trebuie să ruleze.

Dicționare:
• Permite adăugarea de cuvinte considerate valide pentru fiecare limbă.

Despre:
• Identitatea aplicației și o scurtă descriere.

## languages

LayoutSwitcher lucrează cu ID-uri de limbă, nu cu variante de țară:

• EN: surse de intrare engleze precum ABC sau U.S.
• RU: surse de intrare rusești.
• UA: surse de intrare ucrainene. macOS și etichetele de limbă ISO folosesc intern "uk"; asta înseamnă ucraineană, nu engleză britanică.
• RO: surse de intrare românești.

Engleza este partea secundară pentru perechile suportate în prezent:
• Rusă ⇄ Engleză
• Ucraineană ⇄ Engleză
• Română ⇄ Engleză

Detectorul poate evalua toate limbile suportate, dar retastarea efectivă cere o sursă de intrare macOS activată corespunzătoare. Dacă aranjamentul țintă lipsește, aplicația se oprește înainte de orice ștergere.

Diacriticele românești sunt speciale: dacă textul corectat conține caractere specifice românești, aplicația are nevoie de un aranjament românesc care poate să le tasteze.

## romanian-diacritics

Adăugarea automată a diacriticelor românești este o setare opțională din General.

Când este activată, detectorul poate îmbunătăți formele românești cu ASCII simplu:
• "buna" → "bună"
• "tara" → "țară"
• "casa" → "casă"

Condiții:
• Limba activă trebuie să fie română.
• Romanian - Standard trebuie să fie activat dacă rezultatul conține diacritice românești.
• Cuvântul nu trebuie să fie prezent în dicționarul tău utilizator pentru română ca formă simplă explicită.

Adaugă cuvinte în dicționarul român când vrei intenționat ca o scriere ASCII simplu să rămână neschimbată, de exemplu nume, identificatori sau termeni de proiect.

## user-dictionaries

Fiecare limbă suportată are propriul dicționar utilizator.

Un cuvânt adăugat într-un dicționar lingvistic este tratat ca valid pentru acea limbă. Asta ajută detectorul să nu schimbe lucruri tastate intenționat.

Candidați buni:
• Nume și prenume.
• Nume de branduri.
• Nume de proiecte.
• Comenzi tehnice și termeni de produs.
• Cuvinte ASCII românești care nu trebuie să primească diacritice.

Dicționarele sunt locale. Sunt stocate împreună cu setările aplicației și nu sunt încărcate nicăieri.

## exclusions

Unele aplicații nu ar trebui să primească evenimente erase/retype automate: terminale, manageri de parole, jocuri, unele IDE-uri și aplicații cu manipulare proprie a intrărilor.

Adaugă acele aplicații în Setări → Excluderi. Când o aplicație exclusă este focusată, corecțiile automate sunt suprimate înainte de orice ștergere.

Poți adăuga o aplicație și din bara de meniu:
1. Deschide „Ultimele auto-comutări”.
2. Treci cursorul peste o intrare recentă din acea aplicație.
3. Alege „Adaugă <App> în excluderi”.

Conversia manuală a selecției este separată de corecția automată. Tot necesită o scurtătură explicită și o selecție explicită.

## privacy

LayoutSwitcher este local-first:

• Nu trimite textul tastat către un server.
• Nu folosește telemetrie sau analiză.
• Nu salvează buffer-ul de taste live pe disc.
• Resetează buffer-ul de cuvânt la granițele cuvântului și la granițele nesigure de interacțiune.
• Sare câmpurile securizate.

Permisiunea Accesibilitate este necesară pentru a observa evenimentele de tastatură și a retasta corectările. Evenimentele sintetice sunt folosite doar pentru a înlocui ultimul cuvânt încheiat după o greșeală de aranjament.

Stocate local:
• Preferințe.
• Dicționare utilizator.
• ID-uri de bundle excluse.
• Istoric recent al schimbărilor afișat în bara de meniu.
• Contoare de utilizare.

Corecțiile automate pot fi dezactivate pentru aplicațiile selectate în Setări → Excluderi.

Calea clipboard pentru Conversia textului selectat folosește temporar clipboard-ul sistemului. Aplicația salvează conținutul curent al clipboard-ului, copiază textul selectat, îl convertește ca text simplu, îl lipește înapoi și apoi restaurează conținutul original al clipboard-ului.

Corecția automată este intenționat pe cuvânt, deoarece ștergerea automată lungă este riscantă în aplicații terțe. Corecția multi-cuvânt este manuală și bazată pe selecție, astfel încât utilizatorul definește granițele.

## troubleshooting

Nu se întâmplă nimic la tastare:
1. Verifică bara de meniu → Accessibility. Trebuie să arate ca acordată.
2. Verifică că LayoutSwitcher este activat.
3. Verifică că cel puțin două surse de intrare macOS sunt activate.
4. Verifică că aplicația curentă nu este în Excluderi.
5. Verifică că câmpul nu este unul securizat/parolă.

Cuvântul greșit a fost păstrat:
• Apasă comutarea manuală în 3 secunde.
• Adaugă cuvintele reale lipsă în dicționarul utilizator corespunzător.
• Dacă detectorul este prea prudent, încearcă Conservator, Echilibrat sau Agresiv.

Un cuvânt valid a fost schimbat:
• Apasă anularea ultimei comutări automate în 3 secunde.
• Adaugă cuvântul în dicționarul utilizator relevant.
• Dacă asta se întâmplă des, folosește sensibilitatea Conservator.

Conversia textului selectat nu funcționează:
• Asigură-te că textul este într-adevăr selectat.
• Verifică că selecția este sub limita configurată.
• Încearcă o selecție mai mică dacă aplicația țintă blochează API-urile Accessibility pentru text selectat.
• Evită câmpurile securizate și aplicațiile care blochează automatizarea copierii/lipirii.

Diacriticele românești nu funcționează:
• Activează adăugarea automată a diacriticelor românești.
• Comută la română înainte să tastezi.
• Activează Romanian - Standard în sursele de intrare din macOS.

Aranjamentul a rămas blocat:
• Selectează aranjamentul dorit din meniul macOS de surse de intrare, apoi continuă tastarea.
• Asta înseamnă de obicei că macOS a respins o comutare de aranjament în plină execuție.
