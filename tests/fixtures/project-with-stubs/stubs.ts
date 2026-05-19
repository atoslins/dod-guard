// Fixture: TODO markers, empty arrow, suspicious return, not-implemented.

export function createSession(userId: string): Session | null {
  // TODO: actually create the session
  return null;
}

export const updateProfile = (id: string, data: any) => {};

export function fetchInvoice(id: string): Invoice {
  throw new Error("not implemented");
}

export type Session = { id: string };
export type Invoice = { id: string; total: number };
