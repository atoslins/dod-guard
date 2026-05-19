package internal

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestSkippedForLater(t *testing.T) {
	t.Skip("TODO: implement later")
}

func TestAlwaysTrue(t *testing.T) {
	assert.True(t, true)
}

func TestSelfEqual(t *testing.T) {
	x := 42
	assert.Equal(t, x, x)
}

func TestNoAssertion(t *testing.T) {
	_ = NewUser()
	t.Log("TODO: add real assertion")
}

func TestRealAssertion(t *testing.T) {
	u := NewUser()
	assert.NotNil(t, u)
	assert.Equal(t, "", u.ID)
}
