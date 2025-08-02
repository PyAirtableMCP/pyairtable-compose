export default function AuthPage() {
  return (
    <main className="min-h-screen bg-gray-50 flex flex-col justify-center py-12 sm:px-6 lg:px-8">
      <div className="sm:mx-auto sm:w-full sm:max-w-md">
        <h2 className="mt-6 text-center text-3xl font-extrabold text-gray-900">
          PyAirtable Auth
        </h2>
        <p className="mt-2 text-center text-sm text-gray-600">
          Authentication Microservice Frontend
        </p>
        <div className="mt-8 bg-white py-8 px-4 shadow sm:rounded-lg sm:px-10">
          <div className="space-y-4">
            <div className="text-center">
              <span className="inline-flex items-center px-3 py-0.5 rounded-full text-sm font-medium bg-green-100 text-green-800">
                🔐 Auth Service Active
              </span>
            </div>
            <div className="text-center">
              <span className="inline-flex items-center px-3 py-0.5 rounded-full text-sm font-medium bg-blue-100 text-blue-800">
                Port 3001
              </span>
            </div>
          </div>
        </div>
      </div>
    </main>
  )
}
