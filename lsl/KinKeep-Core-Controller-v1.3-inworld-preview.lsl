// KinKeep Core Controller v1.2 — ONE avatar menu + private links + routine reminders
// Put in ROOT prim. Works with existing Secure Pairing and Screen Controller.
string BASE = "https://qnbnxgaxciqcsszfwsly.supabase.co/functions/v1/";
string HOME = "https://lightssonly.github.io/kinkeep-tablet/kinkeep-tablet-v4-calendar-test.html";
integer MAIN_CHANNEL = 984619;
integer YOUTH_CHANNEL = 984625;
integer MENU_CHANNEL = -984619;
key pendingRequest = NULL_KEY;
key pendingAvatar = NULL_KEY;
string pendingType = "";
key reminderRequest = NULL_KEY;
integer pendingSince = 0;
integer reminderSince = 0;
key nativeRequest = NULL_KEY;
key nativeAvatar = NULL_KEY;
integer nativeSince = 0;
integer menuHandle;
integer mainHandle;
integer youthHandle;

integer ready()
{
    return llStringLength(llLinksetDataRead("kk_tablet_id")) == 36 &&
           llStringLength(llLinksetDataRead("kk_device_credential")) == 64;
}
string credentials(string action, key avatar)
{
    return llList2Json(JSON_OBJECT, [
        "action", action,
        "tablet_id", llLinksetDataRead("kk_tablet_id"),
        "device_credential", llLinksetDataRead("kk_device_credential"),
        "avatar_uuid", (string)avatar
    ]);
}
nativeChores(key avatar)
{
    if (!ready()) { llRegionSayTo(avatar, 0, "KinKeep: Pair the tablet first."); return; }
    if (nativeRequest != NULL_KEY) { llRegionSayTo(avatar, 0, "KinKeep: Please try in a moment."); return; }
    nativeAvatar = avatar;
    nativeRequest = llHTTPRequest(BASE + "kinkeep-inworld-chores", [
        HTTP_METHOD, "POST", HTTP_MIMETYPE, "application/json",
        HTTP_BODY_MAXLENGTH, 8192
    ], credentials("my_chores", avatar));
    nativeSince = llGetUnixTime();
}
openMenu(key avatar)
{
    llDialog(avatar, "KinKeep Family Tablet\nWelcome, " + llKey2Name(avatar) +
        "!\nChoose your family space:", [
        "Parent Login", "My Chores", "Rewards", "Goals",
        "Routines", "Home", "Notes", "Calendar", "Close"
    ], MENU_CHANNEL);
}
startPrivate(key avatar, string type)
{
    if (!ready()) {
        llRegionSayTo(avatar, 0, "KinKeep: Pair this tablet first.");
        return;
    }
    if (pendingRequest != NULL_KEY) {
        llRegionSayTo(avatar, 0, "KinKeep: A private link is being prepared. Try again shortly.");
        return;
    }
    string endpoint = BASE + "kinkeep-my-chores";
    if (type == "parent") endpoint = BASE + "kinkeep-parent-login-v2";
    pendingAvatar = avatar;
    pendingType = type;
    pendingRequest = llHTTPRequest(endpoint, [
        HTTP_METHOD, "POST", HTTP_MIMETYPE, "application/json",
        HTTP_BODY_MAXLENGTH, 4096
    ], credentials("begin", avatar));
    if (pendingRequest != NULL_KEY) pendingSince = llGetUnixTime();
    if (pendingRequest == NULL_KEY) {
        pendingAvatar = NULL_KEY;
        pendingType = "";
        llRegionSayTo(avatar, 0, "KinKeep: Could not start private link.");
    }
}
pollReminders()
{
    if (!ready() || reminderRequest != NULL_KEY) return;
    reminderRequest = llHTTPRequest(BASE + "kinkeep-reminder-poll", [
        HTTP_METHOD, "POST", HTTP_MIMETYPE, "application/json",
        HTTP_BODY_MAXLENGTH, 8192
    ], credentials("due", llGetOwner()));
    if (reminderRequest != NULL_KEY) reminderSince = llGetUnixTime();
}
handleChoice(key avatar, string choice)
{
    if (choice == "Parent Login") startPrivate(avatar, "parent");
    else if (choice == "My Chores") nativeChores(avatar);
    else if (choice == "Rewards" ||
             choice == "Goals" || choice == "Routines")
        startPrivate(avatar, "youth");
    else if (choice == "Home" || choice == "Notes" || choice == "Calendar")
        llLoadURL(avatar, "Open KinKeep Home", HOME);
}
deliverReminders(string body)
{
    string arr = llJsonGetValue(body, ["reminders"]);
    if (llJsonValueType(body, ["reminders"]) != JSON_ARRAY) return;
    integer length = llGetListLength(llJson2List(arr));
    integer i;
    for (i = 0; i < length && i < 30; ++i) {
        string prefix = "reminders";
        string id = llJsonGetValue(body, [prefix, i, "id"]);
        string avatarText = llJsonGetValue(body, [prefix, i, "avatar_uuid"]);
        string message = llJsonGetValue(body, [prefix, i, "message"]);
        if (llStringLength(id) != 36 || llStringLength(avatarText) != 36) jump skip;
        key avatar = (key)avatarText;
        integer last = (integer)llLinksetDataRead("kk_rem_" + id);
        integer now = llGetUnixTime();
        if (last > 0 && now - last < 43200) jump skip;
        if (llGetAgentSize(avatar) != ZERO_VECTOR) {
            llRegionSayTo(avatar, 0, "KinKeep Reminder: " + message);
            llLinksetDataWrite("kk_rem_" + id, (string)now);
        }
@skip;
    }
}
default
{
    state_entry()
    {
        mainHandle = llListen(MAIN_CHANNEL, "", NULL_KEY, "");
        youthHandle = llListen(YOUTH_CHANNEL, "", NULL_KEY, "");
        menuHandle = llListen(MENU_CHANNEL, "", NULL_KEY, "");
        pendingRequest = NULL_KEY;
        reminderRequest = NULL_KEY;
        nativeRequest = NULL_KEY;
        nativeAvatar = NULL_KEY;
        nativeSince = 0;
        pendingSince = 0;
        reminderSince = 0;
        llSetTimerEvent(60.0);
        llOwnerSay("KinKeep: Core v1.2 ready — private access + reminders.");
    }
    touch_start(integer total)
    {
        integer i;
        for (i=0; i<total; ++i)
            if (llDetectedType(i) & AGENT) openMenu(llDetectedKey(i));
    }
    listen(integer channel, string name, key id, string message)
    {
        if (llGetAgentSize(id) == ZERO_VECTOR) return;
        string choice = llStringTrim(message, STRING_TRIM);
        if (channel == MAIN_CHANNEL) {
            if (llToLower(choice) == "login") startPrivate(id, "parent");
            else if (llToLower(choice) == "chores") startPrivate(id, "youth");
            else if (llToLower(choice) == "menu") openMenu(id);
        }
        else if (channel == YOUTH_CHANNEL) {
            if (llToLower(choice) == "chores") startPrivate(id, "youth");
        }
        else if (channel == MENU_CHANNEL) handleChoice(id, choice);
    }
    timer()
    {
        integer now = llGetUnixTime();
        if (reminderRequest != NULL_KEY && now - reminderSince > 90)
            reminderRequest = NULL_KEY;
        if (pendingRequest != NULL_KEY && now - pendingSince > 90) {
            llRegionSayTo(pendingAvatar, 0, "KinKeep: Private link timed out. Try again.");
            pendingRequest = NULL_KEY;
            pendingAvatar = NULL_KEY;
            pendingType = "";
        }
        if (nativeRequest != NULL_KEY && now - nativeSince > 90) {
            nativeRequest = NULL_KEY;
            nativeAvatar = NULL_KEY;
        }
        pollReminders();
    }
    http_response(key request_id, integer status, list metadata, string body)
    {
        if (request_id == nativeRequest) {
            key who = nativeAvatar;
            nativeRequest = NULL_KEY;
            nativeAvatar = NULL_KEY;
            if (status != 200) {
                llRegionSayTo(who, 0, "KinKeep: Your in-world chores are unavailable (HTTP " + (string)status + ").");
                return;
            }
            if (llJsonValueType(body, ["chores"]) != JSON_ARRAY) {
                llRegionSayTo(who, 0, "KinKeep: Invalid chore response.");
                return;
            }
            string name = llJsonGetValue(body, ["member_name"]);
            integer count = llGetListLength(llJson2List(llJsonGetValue(body, ["chores"])));
            string output = "KinKeep - " + name + "'s Chores";
            integer i;
            for (i = 0; i < count && i < 6; ++i) {
                string title = llJsonGetValue(body, ["chores", i, "title"]);
                string statusText = llJsonGetValue(body, ["chores", i, "status"]);
                output += "\\n" + (string)(i + 1) + ". " + llGetSubString(title, 0, 35) + " [" + statusText + "]";
            }
            if (count == 0) output += "\\nNo chores assigned yet.";
            llDialog(who, output, ["OK", "My Chores", "Close"], MENU_CHANNEL);
            return;
        }
        if (request_id == reminderRequest) {
            reminderRequest = NULL_KEY;
            if (status == 200) deliverReminders(body);
            return;
        }
        if (request_id != pendingRequest) return;
        key avatar = pendingAvatar;
        string type = pendingType;
        pendingRequest = NULL_KEY;
        pendingAvatar = NULL_KEY;
        pendingType = "";
        if (status != 200) {
            string error = llJsonGetValue(body, ["error"]);
            if (error == JSON_INVALID || error == JSON_NULL || error == "")
                error = "Private access rejected.";
            llRegionSayTo(avatar, 0, "KinKeep: HTTP " + (string)status + " - " + error);
            return;
        }
        string url = llJsonGetValue(body, ["open_url"]);
        if (type == "parent") url = llJsonGetValue(body, ["login_url"]);
        if (llSubStringIndex(url,
            "https://lightssonly.github.io/kinkeep-tablet/") != 0) {
            llRegionSayTo(avatar, 0, "KinKeep: Invalid private link.");
            return;
        }
        llLoadURL(avatar, "Open your private KinKeep page", url);
    }
    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }
}
