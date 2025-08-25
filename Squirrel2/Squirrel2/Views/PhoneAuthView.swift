//
//  PhoneAuthView.swift
//  Squirrel2
//
//  Phone authentication flow views
//

import SwiftUI

struct PhoneAuthView: View {
    @StateObject private var authService = AuthService.shared
    @Environment(\.dismiss) var dismiss
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var showVerificationView = false
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var detectedCountryCode = "+1" // Default to US
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if showVerificationView {
                    VerificationCodeView(
                        verificationCode: $verificationCode,
                        phoneNumber: phoneNumber,
                        isLoading: $isLoading,
                        errorMessage: $errorMessage,
                        onVerify: verifyCode,
                        onResend: resendCode
                    )
                } else {
                    PhoneNumberInputView(
                        phoneNumber: $phoneNumber,
                        isLoading: $isLoading,
                        errorMessage: $errorMessage,
                        onSubmit: sendVerificationCode
                    )
                }
            }
            .navigationTitle(showVerificationView ? "Verify Code" : "Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if showVerificationView {
                        Button("Back") {
                            showVerificationView = false
                            verificationCode = ""
                            errorMessage = ""
                        }
                        .foregroundColor(.squirrelPrimary)
                        .font(.squirrelButtonSecondary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.squirrelTextSecondary)
                    .font(.squirrelButtonSecondary)
                }
            }
            .background(Color.squirrelBackground)
        }
    }
    
    private func sendVerificationCode() {
        guard let formattedNumber = formatAndValidatePhoneNumber() else { return }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                try await authService.sendVerificationCode(to: formattedNumber)
                await MainActor.run {
                    showVerificationView = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    private func verifyCode() {
        guard !verificationCode.isEmpty else {
            errorMessage = "Please enter the verification code"
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                try await authService.verifyCode(verificationCode)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    private func resendCode() {
        sendVerificationCode()
    }
    
    private func formatAndValidatePhoneNumber() -> String? {
        // Remove all non-digit characters except +
        let cleanedNumber = phoneNumber.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        
        if cleanedNumber.isEmpty {
            errorMessage = "Please enter a phone number"
            return nil
        }
        
        var formattedNumber = cleanedNumber
        
        // Auto-add country code if not present
        if !formattedNumber.hasPrefix("+") {
            // Detect country code based on number length and patterns
            if formattedNumber.count == 10 {
                // US/Canada number without country code
                formattedNumber = "+1" + formattedNumber
            } else if formattedNumber.count == 11 && formattedNumber.hasPrefix("1") {
                // US/Canada number with 1 prefix
                formattedNumber = "+" + formattedNumber
            } else {
                // Default to detected country code
                formattedNumber = detectedCountryCode + formattedNumber
            }
        }
        
        // Validate the formatted number
        let digitsOnly = formattedNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if digitsOnly.count < 10 || digitsOnly.count > 15 {
            errorMessage = "Please enter a valid phone number"
            return nil
        }
        
        return formattedNumber
    }
    
    private func formatPhoneNumberForDisplay(_ number: String) -> String {
        let cleanNumber = number.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        // Format US/Canada numbers
        if cleanNumber.count == 10 {
            let index0 = cleanNumber.index(cleanNumber.startIndex, offsetBy: 0)
            let index3 = cleanNumber.index(cleanNumber.startIndex, offsetBy: 3)
            let index6 = cleanNumber.index(cleanNumber.startIndex, offsetBy: 6)
            let index10 = cleanNumber.index(cleanNumber.startIndex, offsetBy: 10)
            
            let areaCode = cleanNumber[index0..<index3]
            let prefix = cleanNumber[index3..<index6]
            let suffix = cleanNumber[index6..<index10]
            
            return "(\(areaCode)) \(prefix)-\(suffix)"
        } else if cleanNumber.count == 11 && cleanNumber.hasPrefix("1") {
            let withoutCountryCode = String(cleanNumber.dropFirst())
            return "+1 " + formatPhoneNumberForDisplay(withoutCountryCode)
        }
        
        // Default formatting for other numbers
        return number
    }
}

struct PhoneNumberInputView: View {
    @Binding var phoneNumber: String
    @Binding var isLoading: Bool
    @Binding var errorMessage: String
    let onSubmit: () -> Void
    
    @State private var formattedPhoneNumber = ""
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.squirrelPrimary)
                    
                    Text("Enter your phone number")
                        .font(.squirrelTitle2)
                        .foregroundColor(.squirrelTextPrimary)
                    
                    Text("We'll send you a verification code")
                        .font(.squirrelSubheadline)
                        .foregroundColor(.squirrelTextSecondary)
                }
                .padding(.top, 40)
                
                // Input
                VStack(spacing: 16) {
                    TextField("(555) 555-5555", text: $phoneNumber)
                        .font(.squirrelBody)
                        .keyboardType(.phonePad)
                        .padding()
                        .background(Color.squirrelSurfaceBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(errorMessage.isEmpty ? Color.clear : Color.red.opacity(0.5), lineWidth: 1)
                        )
                        .disabled(isLoading)
                        .onChange(of: phoneNumber) { newValue in
                            phoneNumber = formatPhoneNumberAsTyping(newValue)
                        }
                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.squirrelFootnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                
                // Submit button
                Button(action: onSubmit) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Text("Send Code")
                            .font(.squirrelButtonPrimary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(phoneNumber.isEmpty ? Color.gray.opacity(0.3) : Color.squirrelPrimary)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .disabled(phoneNumber.isEmpty || isLoading)
                
                #if DEBUG
                // Dev help text
                Text("Dev: Use (555) 555-5555 with code 123456")
                    .font(.squirrelFootnote)
                    .foregroundColor(.squirrelTextSecondary.opacity(0.6))
                    .padding(.top, 8)
                #endif
                
                Spacer()
            }
            .padding(.vertical, 24)
        }
        .background(Color.squirrelBackground)
    }
    
    private func formatPhoneNumberAsTyping(_ number: String) -> String {
        // Remove all non-digit characters
        let cleanNumber = number.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        // Limit to 10 digits for US numbers (or 11 if starts with 1)
        var limitedNumber = cleanNumber
        if cleanNumber.hasPrefix("1") && cleanNumber.count > 11 {
            limitedNumber = String(cleanNumber.prefix(11))
        } else if !cleanNumber.hasPrefix("1") && cleanNumber.count > 10 {
            limitedNumber = String(cleanNumber.prefix(10))
        }
        
        // Format based on length
        if limitedNumber.count == 0 {
            return ""
        } else if limitedNumber.count <= 3 {
            return "(\(limitedNumber)"
        } else if limitedNumber.count <= 6 {
            let areaCode = String(limitedNumber.prefix(3))
            let prefix = String(limitedNumber.dropFirst(3))
            return "(\(areaCode)) \(prefix)"
        } else if limitedNumber.count <= 10 {
            let areaCode = String(limitedNumber.prefix(3))
            let prefixStart = limitedNumber.index(limitedNumber.startIndex, offsetBy: 3)
            let prefixEnd = limitedNumber.index(limitedNumber.startIndex, offsetBy: min(6, limitedNumber.count))
            let prefix = String(limitedNumber[prefixStart..<prefixEnd])
            
            if limitedNumber.count > 6 {
                let suffixStart = limitedNumber.index(limitedNumber.startIndex, offsetBy: 6)
                let suffix = String(limitedNumber[suffixStart...])
                return "(\(areaCode)) \(prefix)-\(suffix)"
            } else {
                return "(\(areaCode)) \(prefix)"
            }
        } else if limitedNumber.count == 11 && limitedNumber.hasPrefix("1") {
            // Format with country code
            let withoutCountryCode = String(limitedNumber.dropFirst())
            let formatted = formatPhoneNumberAsTyping(withoutCountryCode)
            return "+1 \(formatted)"
        }
        
        return String(limitedNumber)
    }
}

struct VerificationCodeView: View {
    @Binding var verificationCode: String
    let phoneNumber: String
    @Binding var isLoading: Bool
    @Binding var errorMessage: String
    let onVerify: () -> Void
    let onResend: () -> Void
    
    @State private var resendTimer = 30
    @State private var canResend = false
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.squirrelPrimary)
                    
                    Text("Verification Code")
                        .font(.squirrelTitle2)
                        .foregroundColor(.squirrelTextPrimary)
                    
                    Text("Code sent to \(phoneNumber)")
                        .font(.squirrelSubheadline)
                        .foregroundColor(.squirrelTextSecondary)
                }
                .padding(.top, 40)
                
                // Code input
                VStack(spacing: 16) {
                    TextField("000000", text: $verificationCode)
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .padding()
                        .background(Color.squirrelSurfaceBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(errorMessage.isEmpty ? Color.clear : Color.red.opacity(0.5), lineWidth: 1)
                        )
                        .disabled(isLoading)
                        .onChange(of: verificationCode) { newValue in
                            // Limit to 6 digits
                            let filtered = newValue.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                            if filtered.count > 6 {
                                verificationCode = String(filtered.prefix(6))
                            } else {
                                verificationCode = filtered
                            }
                        }
                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.squirrelFootnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                
                // Verify button
                Button(action: onVerify) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Text("Verify")
                            .font(.squirrelButtonPrimary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(verificationCode.isEmpty ? Color.gray.opacity(0.3) : Color.squirrelPrimary)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .disabled(verificationCode.isEmpty || isLoading)
                
                // Resend button
                Button(action: {
                    onResend()
                    startResendTimer()
                }) {
                    if canResend {
                        Text("Resend Code")
                            .font(.squirrelButtonSecondary)
                            .foregroundColor(.squirrelPrimary)
                    } else {
                        Text("Resend in \(resendTimer)s")
                            .font(.squirrelButtonSecondary)
                            .foregroundColor(.squirrelTextSecondary)
                    }
                }
                .disabled(!canResend || isLoading)
                .padding(.top, 16)
                
                #if DEBUG
                // Dev help text
                Text("Dev: Use code 123456")
                    .font(.squirrelFootnote)
                    .foregroundColor(.squirrelTextSecondary.opacity(0.6))
                    .padding(.top, 8)
                #endif
                
                Spacer()
            }
            .padding(.vertical, 24)
        }
        .background(Color.squirrelBackground)
        .onAppear {
            startResendTimer()
        }
    }
    
    private func startResendTimer() {
        resendTimer = 30
        canResend = false
        
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if resendTimer > 0 {
                resendTimer -= 1
            } else {
                canResend = true
                timer.invalidate()
            }
        }
    }
}

#Preview {
    PhoneAuthView()
}