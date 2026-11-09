#ifndef CONSOLE_H
#define CONSOLE_H

// ============================================================
//  Console.h - keyboard helpers, accounts, login and display
//
//    Part 1  reading from the keyboard (incl. hidden password typing)
//    Part 2  accounts (sign up, log in, forgot/change password, delete)
//    Part 3  "stay logged in" (one login per session)
//    Part 4  the first screen of the program (loginGate)
//    Part 5  recipe display
// ============================================================

#include <iostream>
#include <cstdlib>
#include <cstdio>       // remove() deletes a file
#include "core/Storage.h"

// Only needed to hide the password while typing. There is one version for
// Windows and one for Linux/Mac - your Windows laptop uses the Windows one.
#ifdef _WIN32
#include <conio.h>      // _getch (reads one key without showing it)
#include <io.h>         // _isatty
#else
#include <csignal>      // Ctrl+C handling
#include <termios.h>    // turns "show typed letters" off
#include <unistd.h>     // isatty, read
#endif
using namespace std;

const string SESSION_FILE = "data/session.txt";      // remembers who is logged in on this computer

// ============================================================
//  PART 1: reading from the keyboard
// ============================================================

// Reads one line from the keyboard. If input is closed (Ctrl+D / end of input),
// we stop safely. Everything is saved at the END of each action, so nothing is lost.
string readLine(){
    string line;
    if(!getline(cin, line)){
        cout << "\nInput ended. Bye!\n";
        exit(0);
    }
    return line;
}

// true if the text is only digits (like "45") and short enough to fit in an int
bool isWholeNumber(string text){
    if(text.size() == 0 || text.size() > 9) return false;
    for(int i = 0; i < (int)text.size(); i++){
        if(text[i] < '0' || text[i] > '9') return false;
    }
    return true;
}

// Asks for a menu number between lowest and highest
int askChoice(string question, int lowest, int highest){
    while(true){
        cout << question;
        string text = trimSpaces(readLine());

        if(isWholeNumber(text)){
            int number = stoi(text);
            if(number >= lowest && number <= highest) return number;
        }
        cout << "Please type a number from " << lowest << " to " << highest << ".\n";
    }
}

// Keeps asking until the user types something (empty answer is not accepted)
string askRequired(string question){
    while(true){
        cout << question;
        string answer = tidyName(readLine());
        if(answer.size() > 0) return answer;
        cout << "This cannot be empty. Please try again.\n";
    }
}

// ------------------------------------------------------------
//  Typing a password: the letters are NOT shown, a * appears for every
//  character instead (so you can see that typing works). Backspace works.
// ------------------------------------------------------------

// adds one typed key to the password; returns true if a * should be shown
// (a non-English letter arrives as 2-3 pieces but must show only ONE *)
bool addPasswordByte(string &pass, char c){
    pass += c;
    return !isContinuationByte(c);
}

// removes the last whole letter; returns true if something was removed
bool removeLastPasswordChar(string &pass){
    if(pass.size() == 0) return false;
    while(pass.size() > 0 && isContinuationByte(pass[pass.size() - 1])){
        pass.pop_back();
    }
    if(pass.size() > 0) pass.pop_back();
    return true;
}

#ifndef _WIN32
// ---- Linux / Mac only (you can ignore this part on Windows) ----
termios savedTerminal;          // the terminal settings from before we changed them
bool terminalSaved = false;

void restoreTerminal(){
    if(terminalSaved){
        tcsetattr(STDIN_FILENO, TCSANOW, &savedTerminal);
        terminalSaved = false;
    }
}

// if Ctrl+C is pressed while typing a password, put the terminal back to normal first
void onInterrupt(int){
    restoreTerminal();
    _exit(130);
}
#endif

string readPassword(string prompt){
    cout << prompt << flush;
    string pass = "";

#ifdef _WIN32
    // ---- Windows version ----
    if(_isatty(_fileno(stdin))){
        while(true){
            int key = _getch();                                   // reads ONE key, shows nothing
            if(key == '\r' || key == '\n') break;                 // Enter = finished
            if(key == 3){ cout << "\n"; exit(0); }                // Ctrl+C
            if(key == 8 || key == 127){                           // Backspace
                if(removeLastPasswordChar(pass)) cout << "\b \b" << flush;
                continue;
            }
            if(key == 0 || key == 224){ _getch(); continue; }     // arrow keys etc: ignore
            if(key < 32) continue;                                // other control keys: ignore
            if(addPasswordByte(pass, (char)key)) cout << '*' << flush;
        }
        cout << "\n";
        return pass;
    }
#else
    // ---- Linux / Mac version ----
    if(isatty(STDIN_FILENO)){
        tcgetattr(STDIN_FILENO, &savedTerminal);
        terminalSaved = true;
        termios typing = savedTerminal;
        typing.c_lflag &= ~(ECHO | ICANON);        // do not show typed letters, give us every key at once
        typing.c_cc[VMIN] = 1;
        typing.c_cc[VTIME] = 0;
        tcsetattr(STDIN_FILENO, TCSANOW, &typing);
        signal(SIGINT, onInterrupt);

        bool inputEnded = false;
        while(true){
            char c = 0;
            if(read(STDIN_FILENO, &c, 1) <= 0){ inputEnded = true; break; }
            if(c == '\n' || c == '\r') break;                          // Enter = finished
            if(c == 4 && pass.size() == 0){ inputEnded = true; break; }  // Ctrl+D
            if(c == 127 || c == 8){                                    // Backspace
                if(removeLastPasswordChar(pass)) cout << "\b \b" << flush;
                continue;
            }
            if(c >= 0 && c < 32) continue;                             // control keys: ignore
            if(addPasswordByte(pass, c)) cout << '*' << flush;
        }

        restoreTerminal();                                             // show typed letters again
        signal(SIGINT, SIG_DFL);
        cout << "\n";
        if(inputEnded){
            cout << "Input ended. Bye!\n";
            exit(0);
        }
        return pass;
    }
#endif

    // not a real keyboard/terminal (for example input coming from a file): normal reading
    pass = readLine();
    if(pass.size() > 0 && pass[pass.size() - 1] == '\r') pass.pop_back();
    return pass;
}
// ============================================================
//  PART 2: accounts (sign up, log in, forgot / change password, delete account)
// ============================================================

// 3-20 characters: letters, numbers, dot (.), underscore (_) or hyphen (-).
// Must start with a letter or number.   Example: M.Abeer  or  abeer_25
bool isValidUsername(string name){
    if(name.size() < 3 || name.size() > 20) return false;
    if(!isLetterOrDigit(name[0])) return false;
    for(int i = 0; i < (int)name.size(); i++){
        char c = name[i];
        if(!isLetterOrDigit(c) && c != '_' && c != '.' && c != '-') return false;
    }
    return true;
}

// Asks for a new password two times (to avoid typing mistakes)
string askNewPassword(){
    while(true){
        string first = readPassword("Choose a password (at least 6 characters): ");
        if(first.size() < 6){
            cout << "Password is too short. Use at least 6 characters.\n";
            continue;
        }
        if(first.size() > 64){
            cout << "Password is too long. Use at most 64 characters.\n";
            continue;
        }
        string second = readPassword("Type the same password again: ");
        if(first != second){
            cout << "The two passwords are not the same. Try again.\n";
            continue;
        }
        return first;
    }
}

// what happens to recipes when an account is deleted (shown at sign up and at deletion)
void showDeletionRule(){
    cout << " IF YOU EVER DELETE YOUR ACCOUNT:\n";
    cout << "  - Your recipes with a good record (average rating " << oneDecimal(GOOD_RECIPE_MIN_AVERAGE)
         << "+ from at least " << GOOD_RECIPE_MIN_RATINGS << " people)\n";
    cout << "    stay on the app as 'Deleted user', so everybody can keep using them.\n";
    cout << "  - Everything else (your other recipes, comments, ratings, likes\n";
    cout << "    and the account itself) is deleted.\n";
}

void showRecoveryCode(string code, bool isNew){
    cout << "\n==================================================\n";
    if(isNew) cout << " ACCOUNT CREATED! Your RECOVERY CODE is:\n";
    else      cout << " Your NEW RECOVERY CODE is (the old one no longer works):\n";
    cout << "\n         " << code << "\n\n";
    cout << " Write it down NOW. It is shown only ONCE.\n";
    cout << " If you forget your password, this code is the only way back in.\n";
    if(isNew){
        cout << "\n";
        showDeletionRule();
    }
    cout << "==================================================\n";
    cout << "Press Enter after you have saved it...";
    readLine();
}

// returns the new user's id, or 0 if cancelled / failed
int signUp(UserDatabase &users){
    if(!users.load()) return 0;

    string username;
    while(true){
        cout << "Choose a username (3-20 characters: letters, numbers, . _ - ; type 0 to cancel): ";
        username = trimSpaces(readLine());

        if(username == "0") return 0;
        if(!isValidUsername(username)){
            cout << "Username must be 3 to 20 characters. Allowed: letters, numbers, dot (.), underscore (_) and hyphen (-).\n";
            cout << "It must start with a letter or a number.  Example: M.Abeer\n";
            continue;
        }
        if(users.findIndexByUsername(username) != -1){
            cout << "This username is already taken. Try another one.\n";
            continue;
        }
        break;
    }

    string password = askNewPassword();

    User newUser;
    newUser.setUsername(username);
    newUser.setId(users.nextUserId());
    newUser.autoSetDate();
    newUser.setPassword(password);
    string recoveryCode = newUser.makeNewRecoveryCode();

    users.addUser(newUser);
    if(!users.save()){
        cout << "Something went wrong, the account was NOT created.\n";
        return 0;
    }

    showRecoveryCode(recoveryCode, true);
    return newUser.getId();
}

// returns the user's id, or 0 if cancelled / wrong
int logIn(UserDatabase &users){
    if(!users.load()) return 0;

    for(int attempt = 1; attempt <= 3; attempt++){
        cout << "Username (type 0 to cancel): ";
        string username = trimSpaces(readLine());
        if(username == "0") return 0;

        string password = readPassword("Password: ");

        int index = users.findIndexByUsername(username);
        if(index != -1 && users.getUsers()[index].checkPassword(password)){
            cout << "Welcome, " << users.getUsers()[index].getUsername() << "!\n";
            return users.getUsers()[index].getId();
        }

        cout << "Wrong username or password. (" << (3 - attempt) << " tries left)\n";

        // shown only after the FIRST wrong try: maybe the person has no account yet
        if(attempt == 1){
            cout << "Don't have an account yet? Type S to sign up now, or just press Enter to try again: ";
            string answer = toLowerCase(trimSpaces(readLine()));
            if(answer == "s" || answer == "y" || answer == "yes"){
                return signUp(users);
            }
        }
    }

    cout << "Too many wrong tries. Going back to the menu.\n";
    return 0;
}

void forgotPassword(UserDatabase &users){
    if(!users.load()) return;

    cout << "Username: ";
    string username = trimSpaces(readLine());
    cout << "Recovery code (like ABCD-EFGH-JKLM): ";
    string code = readLine();

    int index = users.findIndexByUsername(username);
    if(index == -1 || !users.getUsers()[index].checkRecoveryCode(code)){
        cout << "Username or recovery code is wrong.\n";
        return;
    }

    User &user = users.getUsers()[index];
    cout << "Code accepted. Now choose a new password.\n";
    user.setPassword(askNewPassword());
    string newCode = user.makeNewRecoveryCode();
    user.endSession();                 // old "stay logged in" codes stop working

    if(!users.save()){
        cout << "Something went wrong, password was NOT changed.\n";
        return;
    }

    cout << "Password changed successfully!\n";
    showRecoveryCode(newCode, false);
}

void changePassword(UserDatabase &users, int userId){
    if(!users.load()) return;

    int index = users.findIndexById(userId);
    if(index == -1){
        cout << "Account not found.\n";
        return;
    }

    User &user = users.getUsers()[index];
    string current = readPassword("Enter your CURRENT password (leave empty to cancel): ");
    if(current.size() == 0){
        cout << "Cancelled.\n";
        return;
    }
    if(!user.checkPassword(current)){
        cout << "Wrong password. Nothing was changed.\n";
        return;
    }

    user.setPassword(askNewPassword());

    if(users.save()) cout << "Password changed successfully!\n";
    else cout << "Something went wrong, password was NOT changed.\n";
}
// "Biryani > Bombay Biryani  (4.5/5 from 3 ratings)"
string describeRecipe(RecipeDatabase &db, RecipeRef ref){
    Dish &dish = db.getDishes()[ref.dishIndex];
    Variant &variant = dish.getVariants()[ref.variantIndex];

    string text = dish.getName() + " > " + variant.getName();
    if(variant.getRatings().count() == 0){
        text += "  (not rated yet)";
    }
    else{
        string ratingWord = " ratings)";
        if(variant.getRatings().count() == 1) ratingWord = " rating)";
        text += "  (" + oneDecimal(variant.getRatings().average()) + "/5 from "
              + to_string(variant.getRatings().count()) + ratingWord;
    }
    return text;
}

// returns true if the account was deleted
bool deleteAccount(RecipeDatabase &db, UserDatabase &users, int userId){
    if(!users.load() || !db.load()) return false;

    int index = users.findIndexById(userId);
    if(index == -1){
        cout << "Account not found.\n";
        return false;
    }

    DeletionPlan plan = db.planAccountDeletion(userId);

    cout << "\nWARNING: deleting your account cannot be undone.\n";
    cout << "Your comments, ratings and likes will be deleted.\n";

    if(plan.keep.size() == 0 && plan.remove.size() == 0){
        cout << "You have no recipes.\n";
    }
    if(plan.keep.size() > 0){
        cout << "\nThese recipes have a GOOD record, so they will STAY on the app as 'Deleted user':\n";
        for(RecipeRef &ref : plan.keep) cout << "  + " << describeRecipe(db, ref) << "\n";
    }
    if(plan.remove.size() > 0){
        cout << "\nThese recipes will be DELETED:\n";
        for(RecipeRef &ref : plan.remove) cout << "  - " << describeRecipe(db, ref) << "\n";
    }
    cout << "\n";
    showDeletionRule();

    string password = readPassword("\nEnter your password to continue (leave empty to cancel): ");
    if(password.size() == 0){
        cout << "Cancelled. Your account is safe.\n";
        return false;
    }
    if(!users.getUsers()[index].checkPassword(password)){
        cout << "Wrong password. Your account is safe.\n";
        return false;
    }

    cout << "Type DELETE (in capital letters) to confirm: ";
    if(trimSpaces(readLine()) != "DELETE"){
        cout << "Cancelled. Your account is safe.\n";
        return false;
    }

    // load fresh copies right before changing anything (other programs may have changed them meanwhile)
    if(!users.load() || !db.load()) return false;
    index = users.findIndexById(userId);
    if(index == -1){
        cout << "Account not found.\n";
        return false;
    }

    DeletionPlan finalPlan = db.planAccountDeletion(userId);

    // recipes first, then the account (so a failure never leaves recipes of a missing user)
    db.deleteAccountData(userId);
    if(!db.save()){
        cout << "Something went wrong. Nothing was deleted.\n";
        return false;
    }

    users.removeUser(index);
    if(!users.save()){
        cout << "Your recipes were handled but the account could not be removed. Please try again.\n";
        return false;
    }

    remove(SESSION_FILE.c_str());      // forget the saved login of this computer

    cout << "Your account has been deleted. " << finalPlan.keep.size()
         << " recipe(s) stayed as 'Deleted user', " << finalPlan.remove.size() << " were deleted.\n";
    return true;
}
// ============================================================
//  PART 3: "stay logged in"
//  After a successful login we save a small file (session.txt) with the user id and a
//  random secret code (a "token"). users.json keeps only a SCRAMBLED copy of that token.
//  When any program starts, it reads session.txt, checks the token and logs you in by itself.
//  You log in again only after "Log out", or on another computer / a new download.
// ============================================================

// saves the login of this computer
void rememberLogin(UserDatabase &users, int userId){
    if(!users.load()) return;
    int index = users.findIndexById(userId);
    if(index == -1) return;

    string token = randomHex(16);
    users.getUsers()[index].startSession(token);
    if(!users.save()) return;

    ofstream out(SESSION_FILE);
    out << userId << "\n" << token << "\n";
}

// returns the id of the user who is already logged in on this computer, or 0
int loadSavedSession(UserDatabase &users){
    ifstream in(SESSION_FILE);
    if(!in) return 0;

    int userId = 0;
    string token = "";
    in >> userId >> token;
    if(userId <= 0 || token.size() == 0) return 0;      // empty or damaged file

    if(!users.load()) return 0;
    int index = users.findIndexById(userId);
    if(index == -1) return 0;
    if(!users.getUsers()[index].checkSession(token)) return 0;

    return userId;
}

// log out: forget the saved login (the next program will show the login screen)
void logOut(UserDatabase &users, int userId){
    if(users.load()){
        int index = users.findIndexById(userId);
        if(index != -1){
            users.getUsers()[index].endSession();
            users.save();
        }
    }
    remove(SESSION_FILE.c_str());
    cout << "You are logged out.\n";
}

// ============================================================
//  PART 4: the first screen of every program
// ============================================================

// Nobody gets in without an account. If you are already logged in on this computer
// you go straight in. Returns the id of the logged in user, or 0 if the person chose Exit.
int loginGate(UserDatabase &users){
    int savedUserId = loadSavedSession(users);
    if(savedUserId != 0){
        cout << "\nWelcome back, " << users.nameOf(savedUserId) << "! (you are already logged in)\n";
        return savedUserId;
    }

    while(true){
        cout << "\n===== RECIPE APP =====\n";
        cout << "You need an account to use the app.\n";
        cout << " 1. Log in\n";
        cout << " 2. Sign up (create account)\n";
        cout << " 3. Forgot password\n";
        cout << " 0. Exit\n";
        int choice = askChoice("Choice: ", 0, 3);

        if(choice == 0) return 0;

        int userId = 0;
        if(choice == 1) userId = logIn(users);
        else if(choice == 2) userId = signUp(users);
        else forgotPassword(users);

        if(userId != 0){
            rememberLogin(users, userId);
            return userId;
        }
    }
}
// text for a vote - in the Flutter app this decides the colour of the like/dislike buttons
string voteText(int vote){
    if(vote > 0) return "[LIKED]";
    if(vote < 0) return "[DISLIKED]";
    return "no vote";
}

// Shows the recipe, the viewer's own rating/vote, and the comments.
// maxComments = how many of the LATEST comments to show (0 = show all)
void showRecipePage(Dish &dish, Variant &variant, UserDatabase &users, int viewerId, int maxComments){
    variant.show(dish.getName(), users.nameOf(variant.getOwnerId()));

    int myRating = variant.getRatings().getRating(viewerId);
    string myRatingText = "not rated yet";
    if(myRating > 0) myRatingText = to_string(myRating) + "/5";
    cout << "Your rating: " << myRatingText;
    string myProof = variant.getRatings().getProofImageRef(viewerId);
    if(!myProof.empty()) cout << "   Proof: " << myProof;
    cout << "   Your vote: " << voteText(variant.getReactions().getVote(viewerId)) << "\n";

    vector<int> visible = visibleCommentIndexes(variant, viewerId);
    int hiddenFromViewer = (int)variant.getComments().size() - (int)visible.size();

    cout << "COMMENTS (" << visible.size() << "):\n";

    int first = 0;
    if(maxComments > 0 && (int)visible.size() > maxComments){
        first = (int)visible.size() - maxComments;
        cout << " ... " << first << " older comment(s) not shown\n";
    }

    for(int i = first; i < (int)visible.size(); i++){
        Comment &c = variant.getComments()[visible[i]];

        cout << " " << i + 1 << ". " << users.nameOf(c.getUserId());
        if(isOwnerOf(variant, c.getUserId())) cout << " (Owner)";
        cout << "  " << readableDate(c.getCreatedAt());
        if(c.isHidden()) cout << "  [HIDDEN by the owner]";
        cout << "\n    " << c.getText() << "\n";
        cout << "    Likes: " << c.getReactions().likes()
             << "  Dislikes: " << c.getReactions().dislikes()
             << "  Your vote: " << voteText(c.getReactions().getVote(viewerId)) << "\n";
    }

    if(hiddenFromViewer > 0){
        cout << " (" << hiddenFromViewer << " comment(s) hidden by the owner)\n";
    }
}

#endif
