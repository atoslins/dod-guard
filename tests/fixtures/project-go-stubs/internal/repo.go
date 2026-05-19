package internal

import "errors"

type User struct {
	ID    string
	Email string
}

// Uninitialized constructor — DoD-Guard should flag.
func NewUser() *User {
	return &User{}
}

// Action-named fn with no real work.
func CreateUser(email string) (*User, error) {
	// TODO: validate email
	return nil, nil
}

func FetchUser(id string) *User {
	return nil
}

func processOrder() error {
	_, err := lookup()
	_ = err
	return nil
}

func multiSwallow() {
	_, _ = lookup()
}

// nolint:errcheck
func ignored() error {
	return errors.New("placeholder")
}

func lookup() (int, error) {
	panic("not implemented")
}
