/**
 * Simple faker mock for testing
 */
const faker = {
  string: {
    uuid: () => Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15)
  },
  person: {
    fullName: () => 'Test User',
    firstName: () => 'Test',
    lastName: () => 'User',
    jobTitle: () => 'Tester'
  },
  internet: {
    email: () => 'test@example.com'
  },
  company: {
    name: () => 'Test Company'
  },
  phone: {
    number: () => '555-123-4567'
  },
  lorem: {
    paragraph: () => 'This is a test paragraph with some sample text.'
  },
  number: {
    int: (options = {}) => {
      const min = options.min || 0;
      const max = options.max || 100;
      return Math.floor(Math.random() * (max - min + 1)) + min;
    }
  },
  helpers: {
    arrayElement: (array) => array[Math.floor(Math.random() * array.length)]
  }
};

module.exports = faker;