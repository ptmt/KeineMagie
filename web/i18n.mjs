// UI-only copy. Never pass user text, prompt instructions or server content here.
export const interfaceLocales = Object.freeze({de:'Deutsch',en:'English',ru:'Русский',es:'Español',fr:'Français'});
export const interfaceLanguageKey = 'keinemagie:interface-language:v1';
const rows = `Sprache|Language|Язык|Idioma|Langue
Zum Inhalt|Skip to content|К содержимому|Ir al contenido|Aller au contenu
Keine Magie Startseite|Keine Magie home|Главная Keine Magie|Inicio de Keine Magie|Accueil Keine Magie
Bereiche|Sections|Разделы|Secciones|Rubriques
Übersetzer|Translator|Переводчик|Traductor|Traducteur
Diktat|Dictation|Диктовка|Dictado|Dictée
Podcasts|Podcasts|Подкасты|Pódcasts|Podcasts
Coach|Coach|Тренер|Entrenador|Coach
Anmelden|Sign in|Войти|Iniciar sesión|Se connecter
Dein Konto|Your account|Ваш аккаунт|Tu cuenta|Votre compte
Sprachrichtung|Translation direction|Направление перевода|Dirección de traducción|Sens de traduction
Deutsch nach Russisch|German to Russian|С немецкого на русский|Alemán a ruso|Allemand vers russe
Russisch nach Deutsch|Russian to German|С русского на немецкий|Ruso a alemán|Russe vers allemand
Deutsch verbessern|Improve German|Улучшить немецкий|Mejorar alemán|Améliorer l’allemand
Sprachen tauschen|Swap languages|Поменять языки|Intercambiar idiomas|Inverser les langues
Dein Text|Your text|Ваш текст|Tu texto|Votre texte
Leeren|Clear|Очистить|Vaciar|Effacer
Text eingeben …|Enter text …|Введите текст …|Escribe un texto …|Saisissez un texte …
Stil|Style|Стиль|Estilo|Style
Übersetzungsstil|Translation style|Стиль перевода|Estilo de traducción|Style de traduction
Eigenen Stil hinzufügen|Add custom style|Добавить свой стиль|Añadir estilo propio|Ajouter un style personnel
Eigener Stil|Custom style|Свой стиль|Estilo propio|Style personnel
Bearbeiten|Edit|Изменить|Editar|Modifier
Übersetzung|Translation|Перевод|Traducción|Traduction
Kopieren|Copy|Копировать|Copiar|Copier
Kopiert|Copied|Скопировано|Copiado|Copié
Kopieren fehlgeschlagen. Bitte erneut versuchen.|Copy failed. Please try again.|Не удалось скопировать. Попробуйте ещё раз.|No se pudo copiar. Inténtalo de nuevo.|Échec de la copie. Réessayez.
Mit Apple anmelden|Sign in with Apple|Войти с Apple|Iniciar sesión con Apple|Se connecter avec Apple
Sitzung wird geprüft …|Checking session …|Проверка сеанса …|Comprobando sesión …|Vérification de la session …
Abbrechen|Cancel|Отмена|Cancelar|Annuler
Übersetzen|Translate|Перевести|Traducir|Traduire
Verlauf|History|История|Historial|Historique
Aktualisieren|Refresh|Обновить|Actualizar|Actualiser
Melde dich an, um deinen persönlichen Verlauf zu laden.|Sign in to load your personal history.|Войдите, чтобы загрузить свою историю.|Inicia sesión para cargar tu historial.|Connectez-vous pour charger votre historique.
Noch nicht verfügbar|Not available yet|Пока недоступно|Aún no disponible|Pas encore disponible
Podcast hinzufügen|Add podcast|Добавить подкаст|Añadir pódcast|Ajouter un podcast
Podcast-Dialog schließen|Close podcast dialog|Закрыть окно подкаста|Cerrar diálogo de pódcast|Fermer la fenêtre podcast
Hinzufügen als|Add as|Добавить как|Añadir como|Ajouter en tant que
Podcast abonnieren|Subscribe to podcast|Подписаться на подкаст|Suscribirse al pódcast|S’abonner au podcast
Einzelne Folge vorbereiten|Prepare one episode|Подготовить отдельный выпуск|Preparar un episodio|Préparer un épisode
Öffentliche URL|Public URL|Публичная ссылка|URL pública|URL publique
Ein RSS-/Atom-Feed oder eine öffentliche Podcast-Seite. Ein Abo startet keine KI-Verarbeitung.|An RSS/Atom feed or public podcast page. Subscribing does not start AI processing.|RSS/Atom-лента или публичная страница подкаста. Подписка не запускает обработку ИИ.|Un feed RSS/Atom o una página pública de pódcast. Suscribirse no inicia procesamiento de IA.|Un flux RSS/Atom ou une page publique de podcast. L’abonnement ne lance aucun traitement IA.
Abonnieren|Subscribe|Подписаться|Suscribirse|S’abonner
Stil schließen|Close style dialog|Закрыть окно стиля|Cerrar estilo|Fermer le style
Name|Name|Название|Nombre|Nom
Anweisungen für die Übersetzung|Translation instructions|Инструкции для перевода|Instrucciones de traducción|Consignes de traduction
Zum Beispiel: Kurz und freundlich, für eine E-Mail.|For example: Short and friendly, for an email.|Например: Кратко и дружелюбно, для письма.|Por ejemplo: Breve y amable, para un correo.|Par exemple : Bref et amical, pour un e-mail.
Nur in diesem Browser für dein Konto gespeichert, nicht mit der App synchronisiert. Keine Passwörter oder vertraulichen Daten eingeben. Der ausgewählte Stil wird mit der Übersetzung gesendet und im Verlauf gespeichert.|Saved only in this browser for your account, not synced with the app. Do not enter passwords or sensitive data. The selected style is sent with the translation and saved in history.|Сохраняется только в этом браузере для вашего аккаунта, без синхронизации с приложением. Не вводите пароли и конфиденциальные данные. Выбранный стиль отправляется с переводом и сохраняется в истории.|Guardado solo en este navegador para tu cuenta, sin sincronización con la app. No introduzcas contraseñas ni datos confidenciales. El estilo se envía con la traducción y se guarda en el historial.|Enregistré uniquement dans ce navigateur pour votre compte, sans synchronisation avec l’app. Ne saisissez aucun mot de passe ni donnée sensible. Le style est envoyé avec la traduction et conservé dans l’historique.
Löschen|Delete|Удалить|Eliminar|Supprimer
Speichern|Save|Сохранить|Guardar|Enregistrer
Dialog schließen|Close dialog|Закрыть окно|Cerrar diálogo|Fermer la fenêtre
Mit iPhone anmelden|Sign in with iPhone|Войти с iPhone|Iniciar sesión con iPhone|Se connecter avec l’iPhone
Keine Magie auf deinem angemeldeten iPhone öffnen → Browser verbinden. Nur diesen eigenen Browser bestätigen. Der Code gilt fünf Minuten.|Open Keine Magie on your signed-in iPhone → Connect browser. Approve only your own browser. The code expires in five minutes.|Откройте Keine Magie на iPhone, где выполнен вход → Подключить браузер. Подтверждайте только свой браузер. Код действует пять минут.|Abre Keine Magie en tu iPhone con sesión iniciada → Conectar navegador. Confirma solo tu propio navegador. El código dura cinco minutos.|Ouvrez Keine Magie sur votre iPhone connecté → Connecter le navigateur. Confirmez uniquement votre propre navigateur. Le code expire après cinq minutes.
Abmelden|Sign out|Выйти|Cerrar sesión|Se déconnecter
Continue with ChatGPT|Continue with ChatGPT|Продолжить с ChatGPT|Continuar con ChatGPT|Continuer avec ChatGPT
Auf deinem Desktop im KeineMagie-Projekt ausführen:|Run in the KeineMagie project on your desktop:|Выполните на компьютере в проекте KeineMagie:|Ejecuta en el proyecto KeineMagie de tu ordenador:|Exécutez dans le projet KeineMagie sur votre ordinateur :
Server-Adresse und diesen kurzlebigen Einmalcode nur im lokalen Programm eingeben. Das Programm öffnet die offizielle ChatGPT-Zustimmung.|Enter the server address and this short-lived code only in the local program. It opens official ChatGPT authorization.|Введите адрес сервера и этот временный код только в локальной программе. Она откроет официальную страницу авторизации ChatGPT.|Introduce la dirección del servidor y este código temporal solo en el programa local. Abrirá la autorización oficial de ChatGPT.|Saisissez l’adresse du serveur et ce code temporaire uniquement dans le programme local. Il ouvrira l’autorisation officielle ChatGPT.
Einmalcode|One-time code|Одноразовый код|Código de un solo uso|Code à usage unique
Verbindung erneut prüfen|Check connection again|Проверить подключение|Volver a comprobar conexión|Revérifier la connexion
Standard|Default|Обычный|Predeterminado|Par défaut
Freundlich|Friendly|Дружелюбный|Amable|Amical
Formell|Formal|Официальный|Formal|Formel
Aus Verlauf|From history|Из истории|Del historial|De l’historique
Speichern nicht möglich. Name (1–60 Zeichen), Anweisungen (1–1.000 Zeichen) und Browser-Speicher prüfen. Maximal 50 eigene Stile.|Could not save. Check name (1–60 characters), instructions (1–1,000 characters) and browser storage. Maximum 50 custom styles.|Не удалось сохранить. Проверьте название (1–60 символов), инструкции (1–1 000 символов) и хранилище браузера. Максимум 50 своих стилей.|No se pudo guardar. Comprueba nombre (1–60 caracteres), instrucciones (1–1.000) y almacenamiento. Máximo 50 estilos.|Enregistrement impossible. Vérifiez le nom (1–60 caractères), les consignes (1–1 000) et le stockage. Maximum 50 styles.
Löschen nicht möglich. Bitte den Browser-Speicher prüfen.|Could not delete. Check browser storage.|Не удалось удалить. Проверьте хранилище браузера.|No se pudo eliminar. Comprueba el almacenamiento del navegador.|Suppression impossible. Vérifiez le stockage du navigateur.
Wird übersetzt …|Translating …|Переводим …|Traduciendo …|Traduction en cours …
Übersetzen|Translate|Перевести|Traducir|Traduire
Dein ChatGPT-Konto ist verbunden, aber der Modellkatalog ist gerade nicht verfügbar. Bitte die Verbindung erneut prüfen. Eine neue Verbindung ist dafür nicht erforderlich.|Your ChatGPT account is connected, but the model catalog is unavailable. Check the connection again; reconnecting is not required.|Ваш аккаунт ChatGPT подключён, но каталог моделей сейчас недоступен. Проверьте подключение ещё раз; подключать заново не требуется.|Tu cuenta ChatGPT está conectada, pero el catálogo de modelos no está disponible. Comprueba de nuevo; no hace falta reconectar.|Votre compte ChatGPT est connecté, mais le catalogue des modèles est indisponible. Revérifiez la connexion ; inutile de la recréer.
Mit Apple angemeldet|Signed in with Apple|Вход выполнен с Apple|Sesión iniciada con Apple|Connecté avec Apple
Verbindung konnte nicht geprüft werden|Could not check connection|Не удалось проверить подключение|No se pudo comprobar la conexión|Impossible de vérifier la connexion
Verbindung wird geprüft …|Checking connection …|Проверка подключения …|Comprobando conexión …|Vérification de la connexion …
Verbunden · Modell nicht verfügbar|Connected · model unavailable|Подключено · модель недоступна|Conectado · modelo no disponible|Connecté · modèle indisponible
Verbunden|Connected|Подключено|Conectado|Connecté
Nicht verbunden|Not connected|Не подключено|No conectado|Non connecté
Der Status deines persönlichen ChatGPT-Kontos wird geladen.|Loading your personal ChatGPT account status.|Загрузка статуса вашего личного аккаунта ChatGPT.|Cargando el estado de tu cuenta personal de ChatGPT.|Chargement du statut de votre compte ChatGPT personnel.
Dein persönliches ChatGPT-Konto ist verbunden.|Your personal ChatGPT account is connected.|Ваш личный аккаунт ChatGPT подключён.|Tu cuenta personal de ChatGPT está conectada.|Votre compte ChatGPT personnel est connecté.
Verbinde dein eigenes ChatGPT-Konto für Übersetzungen.|Connect your own ChatGPT account for translations.|Подключите свой аккаунт ChatGPT для переводов.|Conecta tu propia cuenta ChatGPT para traducir.|Connectez votre propre compte ChatGPT pour traduire.
Die persönliche ChatGPT-Verbindung ist hier noch nicht verfügbar.|Personal ChatGPT connection is not available here yet.|Подключение личного ChatGPT здесь пока недоступно.|La conexión personal de ChatGPT aún no está disponible aquí.|La connexion ChatGPT personnelle n’est pas encore disponible ici.
Erneut prüfen|Check again|Проверить снова|Volver a comprobar|Revérifier
Konto öffnen|Open account|Открыть аккаунт|Abrir cuenta|Ouvrir le compte
Bereit zum Übersetzen|Ready to translate|Можно переводить|Listo para traducir|Prêt à traduire
ChatGPT verbunden · Modell nicht verfügbar.|ChatGPT connected · model unavailable.|ChatGPT подключён · модель недоступна.|ChatGPT conectado · modelo no disponible.|ChatGPT connecté · modèle indisponible.
ChatGPT im Konto verbinden.|Connect ChatGPT in your account.|Подключите ChatGPT в аккаунте.|Conecta ChatGPT en tu cuenta.|Connectez ChatGPT dans votre compte.
Anmeldung nicht erreichbar.|Sign-in cannot be reached.|Сервис входа недоступен.|No se puede acceder al inicio de sesión.|Connexion inaccessible.
Anmeldung noch nicht verfügbar.|Sign-in is not available yet.|Вход пока недоступен.|Inicio de sesión aún no disponible.|Connexion pas encore disponible.
Melde dich an, um zu übersetzen.|Sign in to translate.|Войдите, чтобы переводить.|Inicia sesión para traducir.|Connectez-vous pour traduire.
Deine Sitzung ist abgelaufen. Bitte erneut anmelden.|Your session expired. Sign in again.|Сеанс истёк. Войдите снова.|Tu sesión ha caducado. Vuelve a iniciar sesión.|Votre session a expiré. Reconnectez-vous.
Diese Anfrage wurde nicht autorisiert. Bitte die Sitzung erneut prüfen.|This request was not authorized. Check your session again.|Запрос не авторизован. Проверьте сеанс.|Solicitud no autorizada. Comprueba la sesión.|Requête non autorisée. Revérifiez la session.
Zu viele Anfragen. Warte bitte einen Moment und versuche es erneut.|Too many requests. Wait a moment and try again.|Слишком много запросов. Подождите и попробуйте снова.|Demasiadas solicitudes. Espera un momento e inténtalo de nuevo.|Trop de requêtes. Patientez et réessayez.
ChatGPT ist nicht verbunden. Bitte dein Konto prüfen.|ChatGPT is not connected. Check your account.|ChatGPT не подключён. Проверьте аккаунт.|ChatGPT no está conectado. Comprueba tu cuenta.|ChatGPT n’est pas connecté. Vérifiez votre compte.
Der Übersetzungsdienst ist gerade nicht verfügbar. Es wurde kein Ergebnis übernommen.|The translation service is unavailable. No result was accepted.|Сервис перевода сейчас недоступен. Результат не сохранён.|Servicio de traducción no disponible. No se ha aceptado ningún resultado.|Service de traduction indisponible. Aucun résultat n’a été accepté.
Keine Verbindung zum Server oder ungültige Antwort. Bitte erneut versuchen.|No server connection or invalid response. Try again.|Нет связи с сервером или неверный ответ. Попробуйте снова.|Sin conexión al servidor o respuesta no válida. Inténtalo de nuevo.|Connexion impossible ou réponse invalide. Réessayez.
ChatGPT-Verbindung konnte nicht geprüft werden. Bitte erneut prüfen.|Could not check ChatGPT connection. Try again.|Не удалось проверить подключение ChatGPT. Попробуйте снова.|No se pudo comprobar ChatGPT. Inténtalo de nuevo.|Impossible de vérifier ChatGPT. Réessayez.
Sitzung konnte nicht geprüft werden. Bitte erneut versuchen.|Could not check your session. Try again.|Не удалось проверить сеанс. Попробуйте снова.|No se pudo comprobar la sesión. Inténtalo de nuevo.|Impossible de vérifier la session. Réessayez.
{source} → {target} · Gespeichert|{source} → {target} · Saved|{source} → {target} · Сохранено|{source} → {target} · Guardado|{source} → {target} · Enregistré
Gespeicherte Übersetzungen öffnen und weiterlernen.|Open saved translations and keep learning.|Открывайте сохранённые переводы и продолжайте учиться.|Abre traducciones guardadas y sigue aprendiendo.|Ouvrez vos traductions enregistrées et continuez à apprendre.
Noch keine Übersetzungen. Dein erstes Ergebnis wird hier gespeichert.|No translations yet. Your first result will be saved here.|Переводов пока нет. Первый результат появится здесь.|Aún no hay traducciones. Tu primer resultado se guardará aquí.|Aucune traduction. Votre premier résultat sera enregistré ici.
Gespeicherte Übersetzung geöffnet.|Saved translation opened.|Сохранённый перевод открыт.|Traducción guardada abierta.|Traduction enregistrée ouverte.
Verlauf wird geladen …|Loading history …|Загрузка истории …|Cargando historial …|Chargement de l’historique …
Bitte erneut anmelden, um deinen Verlauf zu laden.|Sign in again to load your history.|Войдите снова, чтобы загрузить историю.|Vuelve a iniciar sesión para cargar el historial.|Reconnectez-vous pour charger votre historique.
Verlauf konnte nicht geladen werden. Bitte erneut versuchen.|Could not load history. Try again.|Не удалось загрузить историю. Попробуйте снова.|No se pudo cargar el historial. Inténtalo de nuevo.|Impossible de charger l’historique. Réessayez.
Bitte 1 bis 8.000 Zeichen eingeben.|Enter 1 to 8,000 characters.|Введите от 1 до 8 000 символов.|Introduce entre 1 y 8.000 caracteres.|Saisissez entre 1 et 8 000 caractères.
Dein Text wird übersetzt und erklärt …|Translating and explaining your text …|Переводим и объясняем ваш текст …|Traduciendo y explicando tu texto …|Traduction et explication de votre texte …
Übersetzung gespeichert.|Translation saved.|Перевод сохранён.|Traducción guardada.|Traduction enregistrée.
Anfrage abgebrochen. Falls sie bereits abgeschlossen war, prüfe den Verlauf.|Request canceled. If it already completed, check history.|Запрос отменён. Если он уже завершился, проверьте историю.|Solicitud cancelada. Si ya terminó, comprueba el historial.|Requête annulée. Si elle était terminée, consultez l’historique.
Dein Text wird erst beim Übersetzen gesendet.|Your text is sent only when you translate.|Текст отправляется только при переводе.|Tu texto solo se envía al traducir.|Votre texte n’est envoyé qu’au lancement de la traduction.
Text geleert.|Text cleared.|Текст очищен.|Texto borrado.|Texte effacé.
Übersetzung kopiert.|Translation copied.|Перевод скопирован.|Traducción copiada.|Traduction copiée.
Kopieren nicht erlaubt. Markiere den Text und kopiere ihn manuell.|Copying not allowed. Select and copy the text manually.|Копирование запрещено. Выделите и скопируйте текст вручную.|No se permite copiar. Selecciona y copia el texto manualmente.|Copie non autorisée. Sélectionnez et copiez le texte manuellement.
Warte auf ausdrückliche Bestätigung in der iOS-App …|Waiting for explicit approval in the iOS app …|Ожидание подтверждения в приложении iOS …|Esperando confirmación en la app iOS …|En attente de confirmation dans l’app iOS …
Code abgelaufen. Bitte neu beginnen.|Code expired. Start again.|Код истёк. Начните заново.|Código caducado. Empieza de nuevo.|Code expiré. Recommencez.
Verbindung abgelehnt oder abgelaufen. Bitte neu beginnen.|Connection rejected or expired. Start again.|Подключение отклонено или истекло. Начните заново.|Conexión rechazada o caducada. Empieza de nuevo.|Connexion refusée ou expirée. Recommencez.
Gültig bis {time}. Danach „Verbindung erneut prüfen“.|Valid until {time}. Then check the connection again.|Действует до {time}. Затем проверьте подключение снова.|Válido hasta {time}. Después vuelve a comprobar la conexión.|Valable jusqu’à {time}. Ensuite, revérifiez la connexion.
Lokale Inhalte entfernt. Abmeldung wird bestätigt …|Local content cleared. Confirming sign-out …|Локальные данные удалены. Подтверждение выхода …|Contenido local eliminado. Confirmando cierre de sesión …|Contenu local effacé. Confirmation de la déconnexion …
Abgemeldet.|Signed out.|Вы вышли.|Sesión cerrada.|Déconnecté.
Lokale Inhalte entfernt, aber der Server-Widerruf ist nicht bestätigt. Bitte Verbindung erneut prüfen und nochmals abmelden.|Local content cleared, but server revocation is unconfirmed. Check the connection and sign out again.|Локальные данные удалены, но отзыв сеанса на сервере не подтверждён. Проверьте подключение и выйдите снова.|Contenido local eliminado, pero revocación del servidor sin confirmar. Comprueba la conexión y cierra sesión de nuevo.|Contenu local effacé, mais révocation serveur non confirmée. Vérifiez la connexion et déconnectez-vous à nouveau.
In Warteschlange|Queued|В очереди|En cola|En attente
Audio wird geladen|Loading audio|Загрузка аудио|Cargando audio|Chargement de l’audio
Transkription läuft|Transcribing|Распознавание речи|Transcribiendo|Transcription en cours
Übersetzung läuft|Translating|Перевод|Traduciendo|Traduction en cours
Bereit|Ready|Готово|Listo|Prêt
Fehlgeschlagen|Failed|Ошибка|Error|Échec
Abgebrochen|Canceled|Отменено|Cancelado|Annulé
Unbekannter Status|Unknown status|Неизвестный статус|Estado desconocido|État inconnu
Verarbeitungsschritt, kein Audio-Fortschritt|Processing step, not audio progress|Этап обработки, не прогресс аудио|Etapa de procesamiento, no progreso de audio|Étape de traitement, pas progression audio
Erneut versuchen|Try again|Попробовать снова|Reintentar|Réessayer
Diese vorbereitete Folge und ihre Transkripte wirklich löschen?|Delete this prepared episode and its transcripts?|Удалить подготовленный выпуск и его расшифровки?|¿Eliminar este episodio preparado y sus transcripciones?|Supprimer cet épisode préparé et ses transcriptions ?
Melde dich an, um deine Podcasts zu öffnen.|Sign in to open your podcasts.|Войдите, чтобы открыть свои подкасты.|Inicia sesión para abrir tus pódcasts.|Connectez-vous pour ouvrir vos podcasts.
Podcasts werden geladen …|Loading podcasts …|Загрузка подкастов …|Cargando pódcasts …|Chargement des podcasts …
Vorbereitung derzeit nicht verfügbar. Abos und Folgen bleiben zugänglich.|Preparation is unavailable. Subscriptions and episodes remain accessible.|Подготовка сейчас недоступна. Подписки и выпуски остаются доступны.|Preparación no disponible. Suscripciones y episodios siguen accesibles.|Préparation indisponible. Les abonnements et épisodes restent accessibles.
Ungültiger Podcast-Link.|Invalid podcast link.|Неверная ссылка на подкаст.|Enlace de pódcast no válido.|Lien podcast invalide.
← Podcasts|← Podcasts|← Подкасты|← Pódcasts|← Podcasts
Podcast nicht gefunden.|Podcast not found.|Подкаст не найден.|Pódcast no encontrado.|Podcast introuvable.
Podcast-Sprachrichtung|Podcast translation direction|Направление перевода подкаста|Dirección del pódcast|Sens de traduction du podcast
Feed aktualisieren|Refresh feed|Обновить ленту|Actualizar feed|Actualiser le flux
Abo entfernen|Unsubscribe|Отписаться|Cancelar suscripción|Se désabonner
„{title}“ wirklich nicht mehr abonnieren? Vorbereitete Folgen werden nicht gelöscht.|Unsubscribe from “{title}”? Prepared episodes will not be deleted.|Отписаться от «{title}»? Подготовленные выпуски не будут удалены.|¿Cancelar suscripción a «{title}»? Los episodios preparados no se eliminarán.|Se désabonner de « {title} » ? Les épisodes préparés ne seront pas supprimés.
Dieser Feed enthält noch keine verfügbaren Folgen.|This feed has no available episodes yet.|В этой ленте пока нет доступных выпусков.|Este feed aún no tiene episodios disponibles.|Ce flux ne contient pas encore d’épisodes disponibles.
Folge|Episode|Выпуск|Episodio|Épisode
Öffnen|Open|Открыть|Abrir|Ouvrir
Details|Details|Подробнее|Detalles|Détails
Vorbereiten|Prepare|Подготовить|Preparar|Préparer
Vorbereitung nicht gefunden.|Preparation not found.|Подготовка не найдена.|Preparación no encontrada.|Préparation introuvable.
Importierte Folge|Imported episode|Импортированный выпуск|Episodio importado|Épisode importé
Noch keine Folgen|No episodes yet|Выпусков пока нет|Aún sin episodios|Aucun épisode
Einzelne Folgen|Individual episodes|Отдельные выпуски|Episodios individuales|Épisodes individuels
Noch keine Podcasts. Füge über + einen Podcast oder eine einzelne Folge hinzu.|No podcasts yet. Use + to add a podcast or an episode.|Подкастов пока нет. Добавьте подкаст или выпуск через +.|Aún no hay pódcasts. Usa + para añadir un pódcast o episodio.|Aucun podcast. Utilisez + pour ajouter un podcast ou un épisode.
Öffentliche Folge mit direktem Audio. Startet Transkription und Übersetzung über dein Konto.|Public episode with direct audio. Starts transcription and translation through your account.|Публичный выпуск с прямым аудио. Запускает расшифровку и перевод через ваш аккаунт.|Episodio público con audio directo. Inicia transcripción y traducción con tu cuenta.|Épisode public avec audio direct. Lance la transcription et la traduction via votre compte.
Sitzung wird im Hintergrund geprüft …|Checking session in background …|Проверка сеанса в фоне …|Comprobando sesión en segundo plano …|Vérification de la session en arrière-plan …
Alle 4 Podcast-Vorbereitungen für heute wurden verbraucht, auch fehlgeschlagene oder gelöschte. Zurücksetzung um 00:00 UTC. Das persönliche Übersetzungsbudget ist davon getrennt.|All 4 podcast preparations for today are used, including failed or deleted ones. Resets at 00:00 UTC. Your personal translation budget is separate.|Все 4 подготовки подкастов на сегодня использованы, включая неудачные и удалённые. Сброс в 00:00 UTC. Личный лимит переводов учитывается отдельно.|Usadas las 4 preparaciones diarias, incluidas fallidas o eliminadas. Se restablecen a las 00:00 UTC. El presupuesto de traducción es independiente.|Les 4 préparations du jour sont utilisées, y compris celles échouées ou supprimées. Réinitialisation à 00:00 UTC. Le budget de traduction personnel est distinct.
Bereits 2 aktive Podcast-Vorbereitungen. Warte oder brich eine davon ab.|Already 2 active podcast preparations. Wait or cancel one.|Уже выполняются 2 подготовки подкастов. Подождите или отмените одну.|Ya hay 2 preparaciones activas. Espera o cancela una.|Déjà 2 préparations actives. Patientez ou annulez-en une.
Bereits 30 Folgen gespeichert. Lösche eine nicht mehr benötigte inaktive Vorbereitung.|Already 30 episodes saved. Delete an unneeded inactive preparation.|Уже сохранено 30 выпусков. Удалите ненужную неактивную подготовку.|Ya hay 30 episodios guardados. Elimina una preparación inactiva innecesaria.|Déjà 30 épisodes enregistrés. Supprimez une préparation inactive inutile.
Die Warteschlange ist voll. Bitte nach Abschluss laufender Vorbereitungen erneut versuchen.|The queue is full. Try again when current preparations finish.|Очередь заполнена. Попробуйте после завершения текущих подготовок.|La cola está llena. Reintenta al terminar las preparaciones actuales.|La file est pleine. Réessayez après les préparations en cours.
Der Serverspeicher für Podcasts ist voll. Bitte die Administration kontaktieren.|Podcast server storage is full. Contact the administrator.|Хранилище подкастов на сервере заполнено. Обратитесь к администратору.|Almacenamiento del servidor de pódcasts lleno. Contacta al administrador.|Le stockage serveur des podcasts est plein. Contactez l’administration.
Zu viele Anfragen. Bitte später erneut versuchen.|Too many requests. Try again later.|Слишком много запросов. Попробуйте позже.|Demasiadas solicitudes. Reintenta más tarde.|Trop de requêtes. Réessayez plus tard.
Diese Quelle ist nicht verfügbar. Nutze einen öffentlichen RSS-/Atom-Feed oder eine Folge mit direktem Audio, ohne Anmeldung oder signierte URL.|This source is unavailable. Use a public RSS/Atom feed or direct-audio episode without login or signed URL.|Источник недоступен. Используйте публичную RSS/Atom-ленту или выпуск с прямым аудио без входа и подписанной ссылки.|Fuente no disponible. Usa un feed RSS/Atom o episodio con audio directo, sin inicio de sesión ni URL firmada.|Source indisponible. Utilisez un flux RSS/Atom public ou un épisode audio direct sans connexion ni URL signée.
Anfrage nicht autorisiert. Bitte die Sitzung erneut prüfen.|Request not authorized. Check your session again.|Запрос не авторизован. Проверьте сеанс ещё раз.|Solicitud no autorizada. Comprueba de nuevo la sesión.|Requête non autorisée. Revérifiez la session.
Dieser Podcast ist nicht mehr verfügbar.|This podcast is no longer available.|Этот подкаст больше недоступен.|Este pódcast ya no está disponible.|Ce podcast n’est plus disponible.
Aktion in diesem Zustand nicht möglich. Bitte aktualisieren.|Action unavailable in this state. Refresh.|Действие недоступно в этом состоянии. Обновите.|Acción no disponible en este estado. Actualiza.|Action impossible dans cet état. Actualisez.
Vorbereitung derzeit nicht verfügbar. Bitte Worker und persönliche ChatGPT-Verbindung im Konto prüfen.|Preparation is unavailable. Check the worker and personal ChatGPT connection in your account.|Подготовка недоступна. Проверьте обработчик и личное подключение ChatGPT в аккаунте.|Preparación no disponible. Comprueba el worker y tu conexión personal ChatGPT.|Préparation indisponible. Vérifiez le worker et votre connexion ChatGPT personnelle.
Podcasts konnten nicht geladen werden. Bitte erneut versuchen.|Could not load podcasts. Try again.|Не удалось загрузить подкасты. Попробуйте снова.|No se pudieron cargar los pódcasts. Reintenta.|Impossible de charger les podcasts. Réessayez.`.split('\n').map(row=>row.split('|'));
export const interfaceCatalog = Object.freeze(Object.fromEntries(Object.keys(interfaceLocales).map((locale,index)=>[locale,Object.freeze(Object.fromEntries(rows.map(row=>{if(row.length!==5)throw new Error('Invalid UI catalog row');return [row[0],row[index]];})))])));
export function resolveInterfaceLanguage(saved,languages=[]) {
 if(Object.hasOwn(interfaceLocales,saved))return saved;
 for(const value of languages){const base=String(value).toLowerCase().split('-')[0];if(Object.hasOwn(interfaceLocales,base))return base;}
 return 'de';
}
let interfaceLanguage='de';
try{interfaceLanguage=resolveInterfaceLanguage(globalThis.localStorage?.getItem(interfaceLanguageKey),globalThis.navigator?.languages||[globalThis.navigator?.language]);}catch{interfaceLanguage=resolveInterfaceLanguage(null,globalThis.navigator?.languages||[]);}
export const getInterfaceLanguage=()=>interfaceLanguage;
export function t(key,params={}){return (interfaceCatalog[interfaceLanguage][key]??interfaceCatalog.de[key]??key).replace(/\{(\w+)\}/g,(match,name)=>Object.hasOwn(params,name)?String(params[name]):match);}
export function setInterfaceLanguage(value){if(!Object.hasOwn(interfaceLocales,value))return false;interfaceLanguage=value;try{globalThis.localStorage?.setItem(interfaceLanguageKey,value);}catch{/* UI remains usable without storage. */}return true;}
// Bound text is limited to app-owned labels. Reapply without replacing forms or routing.
const bindings=new WeakMap();
export function bindInterfaceText(el,key,params={}){bindings.set(el,{key,params});el.textContent=t(key,params);}
export function unbindInterfaceText(el){bindings.delete(el);}
export function applyInterfaceLanguage(root=document){
 root.documentElement.lang=interfaceLanguage;
 root.querySelectorAll('img[src^="/apple-sign-in-"]').forEach(el=>el.src=`/apple-sign-in-${interfaceLanguage}.png`);
 for(const el of root.querySelectorAll('*')){const binding=bindings.get(el);if(binding)el.textContent=t(binding.key,binding.params);for(const attr of ['aria-label','title','placeholder','alt']){const key=el.getAttribute(`data-i18n-${attr}`);if(key)el.setAttribute(attr,t(key));}}
 root.querySelectorAll('[data-interface-language]').forEach(el=>el.value=interfaceLanguage);
}
// Called once before any asynchronous/user/server content is mounted.
export function registerStaticInterface(root=document){
 for(const el of root.querySelectorAll('body *')){
  if(el.dataset.bootstrapKey)bindInterfaceText(el,el.dataset.bootstrapKey);
  if(el.children.length===0&&!['SCRIPT','STYLE','TEXTAREA','INPUT','CODE'].includes(el.tagName)&&!el.closest('[data-interface-language]')&&Object.hasOwn(interfaceCatalog.de,el.textContent))bindInterfaceText(el,el.textContent);
  for(const attr of ['aria-label','title','placeholder','alt']){const value=el.getAttribute(attr);if(Object.hasOwn(interfaceCatalog.de,value))el.setAttribute(`data-i18n-${attr}`,value);}
 }
 applyInterfaceLanguage(root);
}
