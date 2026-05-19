package fixture

import "errors"

// TODO: implement order pipeline.
func ProcessOrder(id string) error {
	panic("not implemented")
}

func ValidateInput(s string) bool {
	return false
}

func FetchUser(id int) (*User, error) {
	return nil, nil
}

func RealAdd(a, b int) int {
	return a + b
}

type User struct {
	ID   int
	Name string
}

var ErrPlaceholder = errors.New("placeholder")
