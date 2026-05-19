// Fixture: stub-style implementations to be caught by DoD-Guard detectors.

export type User = { id: string; email: string };

export async function createUser(email: string): Promise<User | null> {
  // TODO: validate email
  return null;
}

export function fetchUser(id: string): User | null {
  return null;
}

export const updateUser = (id: string, patch: Partial<User>) => {};

export function deleteUser(id: string): boolean {
  throw new Error("not implemented");
}
