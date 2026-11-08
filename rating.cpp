#include <iostream>
#include "ConsoleTools.h"
using namespace std;

// ============================================================
//  rating.cpp  -  find a recipe, then:
//     rate it (1-5), like / dislike it, write comments,
//     like / dislike comments, delete your own comments,
//     and (recipe owner only) hide / show comments.
//  You must be logged in (you log in only ONCE, the programs remember it).
//  This program is only about recipes. Password / account things are in upload.cpp.
//  Every action: ask -> load newest files -> change -> save.
// ============================================================

// which comments can be picked from the list
const int ANY_COMMENT = 0;          // any comment you can see
const int MY_COMMENTS = 1;          // only comments written by you
const int NOT_HIDDEN_COMMENTS = 2;  // only comments that are not hidden
const int HIDDEN_COMMENTS = 3;      // only hidden comments

bool loadAll(RecipeDatabase &db, UserDatabase &users){
    return db.load() && users.load();
}

// finds the recipe again (newest data); says so if it is gone
bool findRecipe(RecipeDatabase &db, int variantId, RecipeRef &ref){
    ref = db.findVariantById(variantId);
    if(ref.dishIndex == -1){
        cout << "This recipe is no longer available.\n";
        return false;
    }
    return true;
}

// Shows a short numbered list of comments and lets the user pick one.
// Returns the comment's id, or 0 if there is nothing to pick / the user cancels.
int pickComment(Variant &variant, UserDatabase &users, int viewerId, int mode, string question){
    vector<int> visible = visibleCommentIndexes(variant, viewerId);
    vector<int> choices;

    for(int i = 0; i < (int)visible.size(); i++){
        Comment &c = variant.getComments()[visible[i]];
        bool ok = true;
        if(mode == MY_COMMENTS) ok = (c.getUserId() == viewerId);
        else if(mode == NOT_HIDDEN_COMMENTS) ok = !c.isHidden();
        else if(mode == HIDDEN_COMMENTS) ok = c.isHidden();
        if(ok) choices.push_back(visible[i]);
    }

    if(choices.size() == 0){
        cout << "There is no comment to choose.\n";
        return 0;
    }

    cout << "\n";
    for(int i = 0; i < (int)choices.size(); i++){
        Comment &c = variant.getComments()[choices[i]];
        cout << " " << i + 1 << ". " << users.nameOf(c.getUserId()) << ": " << cutText(c.getText(), 60) << "\n";
    }

    int choice = askChoice(question + " (0 to cancel): ", 0, (int)choices.size());
    if(choice == 0) return 0;

    return variant.getComments()[choices[choice - 1]].getId();
}

// ---------------- rating ----------------
void rateRecipe(RecipeDatabase &db, UserDatabase &users, int userId, int variantId){
    RecipeRef ref;
    if(!loadAll(db, users) || !findRecipe(db, variantId, ref)) return;

    // The Stage 1 demo has exactly one user, and the seed recipes are owned by
    // that user. The HTTP API therefore allows rating your own recipe; the
    // console follows the same rule so the rating flow works with the demo data.
    int stars = askChoice("Your rating from 1 (bad) to 5 (excellent), 0 to cancel: ", 0, 5);
    if(stars == 0) return;

    // load the newest data, then save
    if(!loadAll(db, users) || !findRecipe(db, variantId, ref)) return;
    Variant &variant = db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex];

    // The proof image is optional, just like in the API. Pressing Enter keeps
    // an existing proof; typing 'none' removes it; anything else is the new
    // path or URL. setRating() intentionally leaves the proof untouched.
    string existingProof = variant.getRatings().getProofImageRef(userId);
    if(existingProof.empty()){
        cout << "Proof image path or URL (optional, press Enter to skip): ";
    }
    else {
        cout << "Current proof image: " << existingProof << "\n";
        cout << "Proof image path or URL (Enter keeps it, type 'none' to remove): ";
    }
    string proofInput = trimSpaces(readLine());

    bool changed = false;
    if(proofInput.empty()){
        changed = variant.getRatings().setRating(userId, stars);
    }
    else if(toLowerCase(proofInput) == "none"){
        changed = variant.getRatings().setRatingWithProof(userId, stars, "");
    }
    else {
        changed = variant.getRatings().setRatingWithProof(userId, stars, proofInput);
    }

    if(!changed){
        cout << "You had already given this rating. Nothing changed.\n";
        return;
    }

    if(db.save()){
        cout << "Thank you! Your rating: " << stars << "/5\n";
        string proof = variant.getRatings().getProofImageRef(userId);
        if(!proof.empty()) cout << "Proof image: " << proof << "\n";
    }
    else cout << "Something went wrong, your rating was NOT saved.\n";
}

// ---------------- like / dislike the recipe (value: +1 like, -1 dislike) ----------------
void reactToRecipe(RecipeDatabase &db, UserDatabase &users, int userId, int variantId, int value){
    RecipeRef ref;
    if(!loadAll(db, users) || !findRecipe(db, variantId, ref)) return;
    Variant &variant = db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex];

    if(isOwnerOf(variant, userId)){
        cout << "You cannot like or dislike your own recipe.\n";
        return;
    }

    if(!variant.getReactions().setVote(userId, value)){
        if(value > 0) cout << "You have already liked this recipe.\n";
        else cout << "You have already disliked this recipe.\n";
        return;
    }

    if(!db.save()){
        cout << "Something went wrong, your vote was NOT saved.\n";
        return;
    }
    if(value > 0) cout << "You liked this recipe.\n";
    else cout << "You disliked this recipe.\n";
}

// ---------------- write a comment ----------------
void addComment(RecipeDatabase &db, UserDatabase &users, int userId, int variantId){
    string text;
    while(true){
        cout << "Write your comment (max " << MAX_COMMENT_LENGTH << " characters, leave empty to cancel): ";
        text = trimSpaces(readLine());
        if(text.size() == 0){
            cout << "Cancelled.\n";
            return;
        }
        if((int)text.size() > MAX_COMMENT_LENGTH){
            cout << "That comment is too long. Please make it shorter.\n";
            continue;
        }
        break;
    }

    RecipeRef ref;
    if(!loadAll(db, users) || !findRecipe(db, variantId, ref)) return;
    Variant &variant = db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex];

    Comment comment;
    comment.setId(db.nextCommentId());
    comment.setUserId(userId);
    comment.setText(text);
    comment.autoSetDate();
    variant.getComments().push_back(comment);

    if(db.save()) cout << "Comment added.\n";
    else cout << "Something went wrong, your comment was NOT saved.\n";
}

// ---------------- like / dislike a comment ----------------
void reactToComment(RecipeDatabase &db, UserDatabase &users, int userId, int variantId, int value){
    RecipeRef ref;
    if(!loadAll(db, users) || !findRecipe(db, variantId, ref)) return;

    string question = "Which comment do you dislike?";
    if(value > 0) question = "Which comment do you like?";

    int commentId = pickComment(db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex],
                                users, userId, ANY_COMMENT, question);
    if(commentId == 0) return;

    // load the newest data, then save
    if(!loadAll(db, users) || !findRecipe(db, variantId, ref)) return;
    Variant &variant = db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex];

    int index = findCommentIndexById(variant, commentId);
    if(index == -1){
        cout << "This comment no longer exists.\n";
        return;
    }

    Comment &comment = variant.getComments()[index];
    if(comment.getUserId() == userId){
        cout << "You cannot like or dislike your own comment.\n";
        return;
    }

    if(!comment.getReactions().setVote(userId, value)){
        if(value > 0) cout << "You have already liked this comment.\n";
        else cout << "You have already disliked this comment.\n";
        return;
    }

    if(!db.save()){
        cout << "Something went wrong, your vote was NOT saved.\n";
        return;
    }
    if(value > 0) cout << "You liked this comment.\n";
    else cout << "You disliked this comment.\n";
}

// ---------------- delete your own comment ----------------
void deleteMyComment(RecipeDatabase &db, UserDatabase &users, int userId, int variantId){
    RecipeRef ref;
    if(!loadAll(db, users) || !findRecipe(db, variantId, ref)) return;

    int commentId = pickComment(db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex],
                                users, userId, MY_COMMENTS, "Which of your comments do you want to delete?");
    if(commentId == 0) return;

    cout << "Delete this comment permanently? Type yes to confirm: ";
    if(toLowerCase(trimSpaces(readLine())) != "yes"){
        cout << "Cancelled. The comment was not deleted.\n";
        return;
    }

    if(!loadAll(db, users) || !findRecipe(db, variantId, ref)) return;
    Variant &variant = db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex];

    int index = findCommentIndexById(variant, commentId);
    if(index == -1){
        cout << "This comment was already deleted.\n";
        return;
    }
    if(variant.getComments()[index].getUserId() != userId){
        cout << "This comment is not yours. Nothing was deleted.\n";
        return;
    }

    variant.getComments().erase(variant.getComments().begin() + index);

    if(db.save()) cout << "Comment deleted.\n";
    else cout << "Something went wrong, the comment was NOT deleted.\n";
}

// ---------------- hide / show a comment (recipe owner only) ----------------
void hideOrShowComment(RecipeDatabase &db, UserDatabase &users, int userId, int variantId, bool hide){
    RecipeRef ref;
    if(!loadAll(db, users) || !findRecipe(db, variantId, ref)) return;
    Variant &variant = db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex];

    if(!isOwnerOf(variant, userId)){
        cout << "Only the owner of this recipe can hide or show comments.\n";
        return;
    }

    int mode = HIDDEN_COMMENTS;
    string question = "Which comment do you want to SHOW again?";
    if(hide){
        mode = NOT_HIDDEN_COMMENTS;
        question = "Which comment do you want to HIDE?";
    }

    int commentId = pickComment(variant, users, userId, mode, question);
    if(commentId == 0) return;

    if(!loadAll(db, users) || !findRecipe(db, variantId, ref)) return;
    Variant &fresh = db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex];

    if(!isOwnerOf(fresh, userId)){
        cout << "Only the owner of this recipe can hide or show comments.\n";
        return;
    }

    int index = findCommentIndexById(fresh, commentId);
    if(index == -1){
        cout << "This comment no longer exists.\n";
        return;
    }

    fresh.getComments()[index].setHidden(hide);

    if(!db.save()){
        cout << "Something went wrong, nothing was changed.\n";
        return;
    }
    if(hide) cout << "Comment hidden. Other people can no longer read it.\n";
    else cout << "Comment is visible again.\n";
}

// ---------------- the page of ONE recipe ----------------
void recipePage(RecipeDatabase &db, UserDatabase &users, int userId, int variantId){
    while(true){
        RecipeRef ref;
        if(!loadAll(db, users) || !findRecipe(db, variantId, ref)) return;

        Dish &dish = db.getDishes()[ref.dishIndex];
        showRecipePage(dish, dish.getVariants()[ref.variantIndex], users, userId, 0);

        cout << "\nWhat do you want to do?\n";
        cout << " 1. Rate this recipe (1-5)\n";
        cout << " 2. Like this recipe\n";
        cout << " 3. Dislike this recipe\n";
        cout << " 4. Write a comment\n";
        cout << " 5. Like a comment\n";
        cout << " 6. Dislike a comment\n";
        cout << " 7. Delete my comment\n";
        cout << " 8. Hide a comment (recipe owner only)\n";
        cout << " 9. Show a hidden comment again (recipe owner only)\n";
        cout << " 0. Back\n";
        int choice = askChoice("Choice: ", 0, 9);

        if(choice == 0) return;
        else if(choice == 1) rateRecipe(db, users, userId, variantId);
        else if(choice == 2) reactToRecipe(db, users, userId, variantId, 1);
        else if(choice == 3) reactToRecipe(db, users, userId, variantId, -1);
        else if(choice == 4) addComment(db, users, userId, variantId);
        else if(choice == 5) reactToComment(db, users, userId, variantId, 1);
        else if(choice == 6) reactToComment(db, users, userId, variantId, -1);
        else if(choice == 7) deleteMyComment(db, users, userId, variantId);
        else if(choice == 8) hideOrShowComment(db, users, userId, variantId, true);
        else if(choice == 9) hideOrShowComment(db, users, userId, variantId, false);
    }
}

// ---------------- find a recipe, then open its page ----------------
void findAndOpenRecipe(RecipeDatabase &db, UserDatabase &users, int userId, string keyword){
    if(searchWords(keyword).size() == 0){
        cout << "Please type a dish or ingredient name.\n";
        return;
    }

    if(!db.load()) return;
    SearchResult result = searchRecipes(db, keyword);

    // one list: the best matches first, then the others
    vector<RecipeRef> all;
    for(RecipeRef &ref : result.best) all.push_back(ref);
    for(RecipeRef &ref : result.others) all.push_back(ref);

    if(all.size() == 0){
        cout << "No matching recipes found.\n";
        return;
    }

    cout << "\nRecipes found (best rated first):\n";
    for(int i = 0; i < (int)all.size(); i++){
        Dish &dish = db.getDishes()[all[i].dishIndex];
        Variant &variant = dish.getVariants()[all[i].variantIndex];
        cout << " " << i + 1 << ". " << dish.getName() << " > " << variant.getName()
             << "   " << variant.summaryLine() << "\n";
    }

    int choice = askChoice("Open which recipe? Type its number (0 to cancel): ", 0, (int)all.size());
    if(choice == 0) return;

    RecipeRef ref = all[choice - 1];
    int variantId = db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex].getId();

    recipePage(db, users, userId, variantId);
}

int main(){
    // Use the same runtime folder as the Stage 2 server.
    RecipeDatabase db("data");
    UserDatabase users;

    while(true){
        int userId = loginGate(users);          // goes straight in if you are already logged in
        if(userId == 0) break;

        bool loggedIn = true;
        while(loggedIn){
            string keyword;
            cout << "\nSearch a recipe to rate, like or comment on (type 'exit' to quit, 'logout' to log out): ";
            if(!getline(cin, keyword)) return 0;
            keyword = trimSpaces(keyword);

            if(toLowerCase(keyword) == "exit") return 0;

            if(toLowerCase(keyword) == "logout"){
                logOut(users, userId);
                loggedIn = false;
                continue;
            }

            if(keyword.size() == 0){
                cout << "Please type something to search.\n";
                continue;
            }

            findAndOpenRecipe(db, users, userId, keyword);
        }
    }

    return 0;
}