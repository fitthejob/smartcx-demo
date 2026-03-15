import {
  CognitoUserPool,
  CognitoUser,
  AuthenticationDetails,
} from "amazon-cognito-identity-js";

const userPool = new CognitoUserPool({
  UserPoolId: import.meta.env.VITE_COGNITO_USER_POOL_ID,
  ClientId:   import.meta.env.VITE_COGNITO_CLIENT_ID,
});

/**
 * Sign in with email + password.
 * Returns a Promise that resolves to the CognitoUserSession on success.
 * Rejects with { code, message } on failure.
 * Rejects with { code: "NEW_PASSWORD_REQUIRED", cognitoUser } when a forced
 * password change is required (always true for admin-created users on first login).
 */
export function signIn(email, password) {
  return new Promise((resolve, reject) => {
    const cognitoUser = new CognitoUser({ Username: email, Pool: userPool });
    // AuthFlow must be set explicitly — default is USER_SRP_AUTH which requires
    // SRP crypto that the app client is not configured for.
    const authDetails = new AuthenticationDetails({
      Username: email,
      Password: password,
      AuthFlow: "USER_PASSWORD_AUTH",
    });

    cognitoUser.authenticateUser(authDetails, {
      onSuccess: (session) => resolve(session),
      onFailure: (err) => reject({ code: err.code, message: err.message }),
      newPasswordRequired: () => {
        // Surface this as a structured rejection so the UI can handle it
        reject({ code: "NEW_PASSWORD_REQUIRED", cognitoUser });
      },
    });
  });
}

/**
 * Complete the NEW_PASSWORD_REQUIRED challenge after first login.
 * cognitoUser is the object returned in the newPasswordRequired callback.
 */
export function completeNewPassword(cognitoUser, newPassword) {
  return new Promise((resolve, reject) => {
    cognitoUser.completeNewPasswordChallenge(newPassword, {}, {
      onSuccess: (session) => resolve(session),
      onFailure: (err) => reject({ code: err.code, message: err.message }),
    });
  });
}

/**
 * Returns the current user's ID token JWT string, or null if not signed in.
 * The SDK auto-refreshes the session using the refresh token if needed.
 */
export function getIdToken() {
  const cognitoUser = userPool.getCurrentUser();
  if (!cognitoUser) return null;

  // getSession is async but we call it synchronously here; the SDK uses
  // localStorage-cached tokens and only hits the network to refresh.
  let token = null;
  cognitoUser.getSession((err, session) => {
    if (!err && session.isValid()) {
      token = session.getIdToken().getJwtToken();
    }
  });
  return token;
}

/**
 * Returns the current Cognito user object, or null if not signed in.
 */
export function getCurrentUser() {
  return userPool.getCurrentUser();
}

/**
 * Signs out the current user and clears all tokens from localStorage.
 */
export function signOut() {
  const cognitoUser = userPool.getCurrentUser();
  if (cognitoUser) cognitoUser.signOut();
}
