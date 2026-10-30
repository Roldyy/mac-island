enum TextEditingRole {
    /// Finder rename and the search field are text fields: shortcuts there belong to the text.
    static func isTextEditing(role: String?, subrole: String?) -> Bool {
        if let role, ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role) { return true }
        return subrole == "AXSearchField"
    }
}
