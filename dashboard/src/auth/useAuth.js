import { useState, useEffect, useCallback } from "react";
import {
  getCurrentUser,
  signIn as cognitoSignIn,
  completeNewPassword as cognitoCompleteNewPassword,
  signOut as cognitoSignOut,
} from "./cognitoClient";

/**
 * Hook that manages Cognito auth state.
 *
 * Returns:
 *   user         — CognitoUser object when signed in, null otherwise
 *   loading      — true during initial session check
 *   error        — error message string or null
 *   newPasswordRequired — true when first-login password change is needed
 *   pendingUser  — CognitoUser object held during the NEW_PASSWORD_REQUIRED challenge
 *   signIn(email, password)
 *   completeNewPassword(newPassword)
 *   signOut()
 */
export function useAuth() {
  const [user, setUser]                             = useState(null);
  const [loading, setLoading]                       = useState(true);
  const [error, setError]                           = useState(null);
  const [newPasswordRequired, setNewPasswordRequired] = useState(false);
  const [pendingUser, setPendingUser]               = useState(null);

  // On mount: check if there's an existing valid session in localStorage
  useEffect(() => {
    const cognitoUser = getCurrentUser();
    if (!cognitoUser) {
      setLoading(false);
      return;
    }
    cognitoUser.getSession((err, session) => {
      if (!err && session.isValid()) {
        setUser(cognitoUser);
      }
      setLoading(false);
    });
  }, []);

  const signIn = useCallback(async (email, password) => {
    setError(null);
    try {
      await cognitoSignIn(email, password);
      setUser(getCurrentUser());
    } catch (err) {
      if (err.code === "NEW_PASSWORD_REQUIRED") {
        setNewPasswordRequired(true);
        setPendingUser(err.cognitoUser);
      } else {
        setError(err.message || "Sign in failed.");
      }
    }
  }, []);

  const completeNewPassword = useCallback(async (newPassword) => {
    setError(null);
    try {
      await cognitoCompleteNewPassword(pendingUser, newPassword);
      setNewPasswordRequired(false);
      setPendingUser(null);
      setUser(getCurrentUser());
    } catch (err) {
      setError(err.message || "Password change failed.");
    }
  }, [pendingUser]);

  const signOut = useCallback(() => {
    cognitoSignOut();
    setUser(null);
    setError(null);
    setNewPasswordRequired(false);
    setPendingUser(null);
  }, []);

  return { user, loading, error, newPasswordRequired, signIn, completeNewPassword, signOut };
}
