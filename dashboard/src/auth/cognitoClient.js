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
    // Must call setAuthenticationFlowType before authenticateUser —
    // AuthenticationDetails does not control the flow; this method does.
    cognitoUser.setAuthenticationFlowType("USER_PASSWORD_AUTH");
    const authDetails = new AuthenticationDetails({ Username: email, Password: password });

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
 * Returns a Promise resolving to the current ID token JWT string,
 * or null if not signed in. The SDK auto-refreshes if the token is expired.
 */
export function getIdToken() {
  return new Promise((resolve) => {
    const cognitoUser = userPool.getCurrentUser();
    if (!cognitoUser) return resolve(null);
    cognitoUser.getSession((err, session) => {
      if (!err && session.isValid()) {
        resolve(session.getIdToken().getJwtToken());
      } else {
        resolve(null);
      }
    });
  });
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
